import MapboxVision
import MapboxVisionARNative
import MetalKit

/* Render coordinate system:
 *      Y
 *      ^
 *      |
 *      0 -----> X
 *     /
 *    /
 *   Z
 */

/* World coordinate system:
 *       Z
 *       ^  X
 *       | /
 *       |/
 * Y <-- 0
 */

class ARRenderer: NSObject {
    // MARK: Public properties

    /// The `ARScene` object to be rendered.
    let scene = ARScene()

    var frame: CVPixelBuffer?
    var camera: ARCamera?
    var lane: ARLane?

    // MARK: Private properties

    /// The Metal device this renderer uses for rendering.
    private let device: MTLDevice
    /// The Metal command queue this renderer uses for rendering.
    private let commandQueue: MTLCommandQueue

    private let samplerStateDefault: MTLSamplerState
    private let depthStencilStateDefault: MTLDepthStencilState

    #if !targetEnvironment(simulator)
    private var textureCache: CVMetalTextureCache?
    #endif

    private let vertexDescriptor: MDLVertexDescriptor = ARRenderer.makeVertexDescriptor()
    private let backgroundVertexBuffer: MTLBuffer
    private let renderPipelineDefault: MTLRenderPipelineState
    private let renderPipelineArrow: MTLRenderPipelineState
    private let renderPipelineBackground: MTLRenderPipelineState

    private var viewProjectionMatrix = matrix_identity_float4x4

    // MARK: Lifecycle

    /**
     Creates a renderer with the specified Metal device.

     - Parameters:
       - device: A Metal device used for drawing.
       - colorPixelFormat: The color pixel format for the current drawable's texture.
       - depthStencilPixelFormat: The format used to generate the packed depth/stencil texture.

     - Returns: A new renderer object.
     */
    init(device: MTLDevice, colorPixelFormat: MTLPixelFormat, depthStencilPixelFormat: MTLPixelFormat) throws {
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else { throw ARRendererError.cantCreateCommandQueue }
        self.commandQueue = commandQueue
        self.commandQueue.label = "com.mapbox.ARRenderer"

        #if !targetEnvironment(simulator)
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) == kCVReturnSuccess else {
            throw ARRendererError.cantCreateTextureCache
        }
        #endif

        let library = try device.makeDefaultLibrary(bundle: Bundle(for: type(of: self)))
        guard
            let defaultVertexFunction = library.makeFunction(name: ARConstants.ShaderName.defaultVertexMain),
            let arrowVertexFunction = library.makeFunction(name: ARConstants.ShaderName.arrowVertexMain),
            let backgroundVertexFunction = library.makeFunction(name: ARConstants.ShaderName.mapTextureVertex),
            let defaultFragmentFunction = library.makeFunction(name: ARConstants.ShaderName.defaultFragmentMain),
            let arrowFragmentFunction = library.makeFunction(name: ARConstants.ShaderName.laneFragmentMain),
            let backgroundFragmentFunction = library.makeFunction(name: ARConstants.ShaderName.displayTextureFragment)
            else {
                throw ARRendererError.cantFindFunctions
        }

        renderPipelineDefault = try ARRenderer.makeRenderPipeline(
            device: device,
            vertexDescriptor: vertexDescriptor,
            vertexFunction: defaultVertexFunction,
            fragmentFunction: defaultFragmentFunction,
            colorPixelFormat: colorPixelFormat,
            depthStencilPixelFormat: depthStencilPixelFormat
        )

        renderPipelineArrow = try ARRenderer.makeRenderPipeline(
            device: device,
            vertexDescriptor: vertexDescriptor,
            vertexFunction: arrowVertexFunction,
            fragmentFunction: arrowFragmentFunction,
            colorPixelFormat: colorPixelFormat,
            depthStencilPixelFormat: depthStencilPixelFormat
        )

        renderPipelineBackground = try ARRenderer.makeRenderBackgroundPipeline(
            device: device,
            vertexDescriptor: ARRenderer.makeTextureMappingVertexDescriptor(),
            vertexFunction: backgroundVertexFunction,
            fragmentFunction: backgroundFragmentFunction,
            colorPixelFormat: colorPixelFormat,
            depthStencilPixelFormat: depthStencilPixelFormat
        )

        samplerStateDefault = ARRenderer.makeDefaultSamplerState(device: device)
        depthStencilStateDefault = ARRenderer.makeDefaultDepthStencilState(device: device)

        guard let buffer = device.makeBuffer(bytes: ARConstants.textureMappingVertices,
                                             length: ARConstants.textureMappingVertices.count * MemoryLayout<Float>.size,
                                             options: [])
        else { throw ARRendererError.cantCreateBuffer }
        backgroundVertexBuffer = buffer

        super.init()
    }

    // MARK: Public functions

    func initARSceneForARLane() {
        scene.rootNode.removeAllChilds()

        let arLaneMesh = ARLaneMesh(device: device, vertexDescriptor: vertexDescriptor)
        let arLaneEntity = ARLaneEntity(with: arLaneMesh, and: renderPipelineArrow)
        let arrowNode = ARLaneNode(arLaneEntity: arLaneEntity)
        arrowNode.set(laneWidth: 3.0)
        scene.rootNode.add(child: arrowNode)
    }

    func drawScene(commandEncoder: MTLRenderCommandEncoder, lane: ARLane) {
        commandEncoder.setFrontFacing(.counterClockwise)
        commandEncoder.setCullMode(.back)
        commandEncoder.setDepthStencilState(depthStencilStateDefault)
        commandEncoder.setRenderPipelineState(renderPipelineDefault)
        commandEncoder.setFragmentSamplerState(samplerStateDefault, index: 0)

        let viewMatrix = makeViewMatrix(
            trans: scene.cameraNode.geometry.position,
            rot: scene.cameraNode.geometry.rotation
        )
        viewProjectionMatrix = scene.cameraNode.projectionMatrix() * viewMatrix

        scene.rootNode.childs.forEach { arNode in
            if let arNode = arNode as? ARNode, let arEntity = arNode.entity, let mesh = arEntity.mesh {
                commandEncoder.setRenderPipelineState(arEntity.renderPipeline ?? renderPipelineDefault)

                let modelMatrix = arNode.worldTransform()
                let material = arEntity.material

                if arNode.nodeType == .arrowNode {
                    let points = lane.curve.getControlPoints()

                    guard points.count == 4 else {
                        assertionFailure("ARLane should contains four points")
                        return
                    }

                    var vertexUniforms = ArrowVertexUniforms(
                        viewProjectionMatrix: viewProjectionMatrix,
                        modelMatrix: modelMatrix,
                        normalMatrix: normalMatrix(mat: modelMatrix),
                        p0: ARRenderer.processPoint(points[0]),
                        p1: ARRenderer.processPoint(points[1]),
                        p2: ARRenderer.processPoint(points[2]),
                        p3: ARRenderer.processPoint(points[3])
                    )
                    commandEncoder.setVertexBytes(&vertexUniforms, length: MemoryLayout<ArrowVertexUniforms>.size, index: 1)
                } else {
                    var vertexUniforms = DefaultVertexUniforms(
                        viewProjectionMatrix: viewProjectionMatrix,
                        modelMatrix: modelMatrix,
                        normalMatrix: normalMatrix(mat: modelMatrix)
                    )
                    commandEncoder.setVertexBytes(&vertexUniforms, length: MemoryLayout<DefaultVertexUniforms>.size, index: 1)
                }

                var fragmentUniforms = FragmentUniforms(cameraWorldPosition: scene.cameraNode.geometry.position,
                                                        ambientLightColor: material.ambientLightColor,
                                                        specularColor: material.specularColor,
                                                        baseColor: material.diffuseColor.xyz,
                                                        opacity: material.diffuseColor.w,
                                                        specularPower: material.specularPower,
                                                        light: material.light ?? ARLight.defaultLightForLane())

                commandEncoder.setFragmentBytes(&fragmentUniforms, length: MemoryLayout<FragmentUniforms>.size, index: 0)
                commandEncoder.setFrontFacing(material.frontFaceMode)

                let vertexBuffer = mesh.vertexBuffers.first!
                commandEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: 0)

                for submesh in mesh.submeshes {
                    let indexBuffer = submesh.indexBuffer
                    commandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                         indexCount: submesh.indexCount,
                                                         indexType: submesh.indexType,
                                                         indexBuffer: indexBuffer.buffer,
                                                         indexBufferOffset: indexBuffer.offset)
                }
            }
        }
    }

    // MARK: Private functions

    private func update(_ view: MTKView) {
        guard let camParams = camera else { return }
        scene.cameraNode.aspectRatio = camParams.aspectRatio
        scene.cameraNode.fovRadians = camParams.fov
        scene.cameraNode.geometry.rotation = simd_quatf.byAxis(camParams.roll - Float.pi / 2, -camParams.pitch, 0)

        scene.cameraNode.geometry.position = float3(0, camParams.height, 0)
    }


    func makeTexture(from buffer: CVPixelBuffer) -> MTLTexture? {
        #if !targetEnvironment(simulator)
        var imageTexture: CVMetalTexture?
        guard
            let textureCache = textureCache,
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                      textureCache,
                                                      buffer,
                                                      nil,
                                                      .bgra8Unorm,
                                                      CVPixelBufferGetWidth(buffer),
                                                      CVPixelBufferGetHeight(buffer),
                                                      0,
                                                      &imageTexture) == kCVReturnSuccess
            else { return nil }
        return CVMetalTextureGetTexture(imageTexture!)
        #else
        return nil
        #endif
    }
}

extension ARRenderer {
    // MARK: Static functions

    static func makeVertexDescriptor() -> MDLVertexDescriptor {
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        vertexDescriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3,
            offset: MemoryLayout<Float>.size * 3,
            bufferIndex: 0
        )
        vertexDescriptor.attributes[2] = MDLVertexAttribute(
            name: MDLVertexAttributeTextureCoordinate,
            format: .float2,
            offset: MemoryLayout<Float>.size * 6,
            bufferIndex: 0
        )
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 8)
        return vertexDescriptor
    }

    static func makeTextureMappingVertexDescriptor() -> MTLVertexDescriptor {
        let vertexDescriptor = MTLVertexDescriptor()

        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 3
        vertexDescriptor.attributes[1].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 5
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        return vertexDescriptor
    }

    static func makeRenderBackgroundPipeline(
        device: MTLDevice,
        vertexDescriptor: MTLVertexDescriptor,
        vertexFunction: MTLFunction,
        fragmentFunction: MTLFunction,
        colorPixelFormat: MTLPixelFormat,
        depthStencilPixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        let pipeline = MTLRenderPipelineDescriptor()
        pipeline.vertexFunction = vertexFunction
        pipeline.fragmentFunction = fragmentFunction

        pipeline.colorAttachments[0].pixelFormat = colorPixelFormat
        pipeline.depthAttachmentPixelFormat = depthStencilPixelFormat

        pipeline.vertexDescriptor = vertexDescriptor

        return try device.makeRenderPipelineState(descriptor: pipeline)
    }

    static func makeRenderPipeline(
        device: MTLDevice,
        vertexDescriptor: MDLVertexDescriptor,
        vertexFunction: MTLFunction,
        fragmentFunction: MTLFunction,
        colorPixelFormat: MTLPixelFormat,
        depthStencilPixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        let pipeline = MTLRenderPipelineDescriptor()
        pipeline.vertexFunction = vertexFunction
        pipeline.fragmentFunction = fragmentFunction

        pipeline.colorAttachments[0].pixelFormat = colorPixelFormat
        pipeline.colorAttachments[0].isBlendingEnabled = true
        pipeline.colorAttachments[0].rgbBlendOperation = MTLBlendOperation.add
        pipeline.colorAttachments[0].alphaBlendOperation = MTLBlendOperation.add
        pipeline.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactor.sourceAlpha
        pipeline.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactor.sourceAlpha
        pipeline.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
        pipeline.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
        pipeline.depthAttachmentPixelFormat = depthStencilPixelFormat

        let mtlVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)
        pipeline.vertexDescriptor = mtlVertexDescriptor

        return try device.makeRenderPipelineState(descriptor: pipeline)
    }

    static func makeDefaultSamplerState(device: MTLDevice) -> MTLSamplerState {
        let sampler = MTLSamplerDescriptor()

        sampler.minFilter = .linear
        sampler.mipFilter = .linear
        sampler.magFilter = .linear

        sampler.normalizedCoordinates = true
        return device.makeSamplerState(descriptor: sampler)!
    }

    static func makeDefaultDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
        let depthStencil = MTLDepthStencilDescriptor()

        depthStencil.isDepthWriteEnabled = true
        depthStencil.depthCompareFunction = .less

        return device.makeDepthStencilState(descriptor: depthStencil)!
    }

    static func processPoint(_ coordinate: WorldCoordinate) -> float3 {
        return float3(Float(-coordinate.y), Float(coordinate.z), Float(-coordinate.x))
    }
}

extension ARRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // TODO: update camera
    }

    func draw(in view: MTKView) {
        update(view)

        // render
        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let renderPass = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable
            else { return }

        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)
            else { return }

        if let frame = frame, let texture = makeTexture(from: frame) {
            commandEncoder.setRenderPipelineState(renderPipelineBackground)
            commandEncoder.setVertexBuffer(backgroundVertexBuffer, offset: 0, index: 0)
            commandEncoder.setFragmentTexture(texture, index: 0)
            commandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: ARConstants.textureMappingVertices.count)
        }

        if let lane = lane {
            drawScene(commandEncoder: commandEncoder, lane: lane)
        }

        commandEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
