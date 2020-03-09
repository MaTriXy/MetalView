import Alloy
import UIKit
import simd
import SwiftMath

public class MetalView: UIView {

    // MARK: - Type Definitions

    public enum TextureContentMode {
        case resize
        case aspectFill
        case aspectFit
    }

    // MARK: - Properties

    public var context: MTLContext!

    public var pixelFormat: MTLPixelFormat {
        get { self.layer.pixelFormat }
        set {
            self.layer.pixelFormat = newValue
            self.updateRenderPipelineState()
        }
    }

    public var colorSpace: CGColorSpace? {
        get { self.layer.colorspace }
        set { self.layer.colorspace = newValue }
    }

    public var drawableSize: CGSize {
        get { self.layer.drawableSize }
        set { self.layer.drawableSize = newValue }
    }

    public var autoResizeDrawable: Bool = true {
        didSet {
            if self.autoResizeDrawable {
                self.setNeedsLayout()
            }
        }
    }

    public var textureContentMode: TextureContentMode = .aspectFill {
        didSet {
            if !self.needsAdaptToTextureInput {
                self.setNeedsAdaptToTextureInput()
            }
        }
    }

    public override var layer: CAMetalLayer {
        return super.layer as! CAMetalLayer
    }

    public override class var layerClass: AnyClass {
        return CAMetalLayer.self
    }

    private let renderPassDescriptor: MTLRenderPassDescriptor = {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].clearColor = .init(red: 0,
                                                          green: 0,
                                                          blue: 0,
                                                          alpha: 0)
        return descriptor
    }()
    private var renderPipelineState: MTLRenderPipelineState
    private var needsAdaptToTextureInput = true
    private var projectionMatrix = Matrix4x4f.identity

    // MARK: - Life Cycle

    public init(context: MTLContext,
                pixelFormat: MTLPixelFormat = .bgra8Unorm) throws {
        self.context = context
        self.renderPipelineState = Self.makeRenderState(for: context,
                                                        pixelFormat: pixelFormat)

        super.init(frame: .zero)
        try self.setup(pixelFormat: pixelFormat)
    }

    required init?(coder aDecoder: NSCoder) {
        do {
            let context = try MTLContext()
            self.renderPipelineState = Self.makeRenderState(for: context,
                                                            pixelFormat: .bgra8Unorm)
            super.init(coder: aDecoder)
            try self.setup()
        } catch {
            return nil
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        if self.autoResizeDrawable {
            var size = self.bounds.size
            size.width *= self.contentScaleFactor
            size.height *= self.contentScaleFactor

            self.layer.drawableSize = size

            if !self.needsAdaptToTextureInput {
                self.setNeedsAdaptToTextureInput()
            }
        }
    }

    // MARK: - Setup

    private func setup(pixelFormat: MTLPixelFormat = .bgra8Unorm) throws {
        self.setupLayer(pixelFormat: pixelFormat)
        self.backgroundColor = .clear
    }

    private func setupLayer(pixelFormat: MTLPixelFormat) {
        self.layer.device = self.context.device
        self.layer.pixelFormat = pixelFormat
        self.layer.framebufferOnly = true
        self.layer.isOpaque = true
        self.layer.maximumDrawableCount = 3

        self.backgroundColor = .clear
    }

    public func updateRenderPipelineState() {
        self.renderPipelineState = Self.makeRenderState(for: self.context,
                                                        pixelFormat: self.layer.pixelFormat)
    }

    public func setNeedsAdaptToTextureInput() {
        self.needsAdaptToTextureInput = true
    }

    // MARK: - Helpers

    private func recalculateProjectionMatrix(using textureSize: MTLSize) {
        let drawableAspectRatio: Float = .init(self.layer.drawableSize.width)
                                       / .init(self.layer.drawableSize.height)
        let textureAspectRatio: Float = .init(textureSize.width)
                                      / .init(textureSize.height)
        let normalizationValue = drawableAspectRatio / textureAspectRatio

        var normlizedTextureWidth: Float
        var normlizedTextureHeight: Float

        switch self.textureContentMode {
        case .resize:
            normlizedTextureWidth = 1.0
            normlizedTextureHeight = 1.0
        case .aspectFill:
            normlizedTextureWidth = normalizationValue < 1.0
                                                       ? 1.0 / normalizationValue
                                                       : 1.0
            normlizedTextureHeight = normalizationValue < 1.0
                                                       ? 1.0
                                                       : normalizationValue
        case .aspectFit:
            normlizedTextureWidth = normalizationValue > 1.0
                                                       ? 1 / normalizationValue
                                                       : 1.0
            normlizedTextureHeight = normalizationValue > 1.0
                                                        ? 1.0
                                                        : normalizationValue
        }

        self.projectionMatrix = .scale(sx: normlizedTextureWidth,
                                       sy: normlizedTextureHeight,
                                       sz: 1.0)
    }

    private func normlizedTextureSize(from textureSize: MTLSize) -> SIMD2<Float> {
        let drawableAspectRatio: Float = .init(self.layer.drawableSize.width)
                                       / .init(self.layer.drawableSize.height)
        let textureAspectRatio: Float = .init(textureSize.width)
                                      / .init(textureSize.height)
        let normlizedTextureWidth = drawableAspectRatio < textureAspectRatio
                                  ? 1.0
                                  : drawableAspectRatio / textureAspectRatio
        let normlizedTextureHeight = drawableAspectRatio > textureAspectRatio
                                   ? 1.0
                                   : drawableAspectRatio / textureAspectRatio
        return .init(x: normlizedTextureWidth,
                     y: normlizedTextureHeight)
    }

    // MARK: Draw

    /// Draw a texture
    ///
    /// - Note: This method should be called on main thread only.
    ///
    /// - Parameters:
    ///   - texture: texture to draw
    ///   - additionalRenderCommands: render commands to execute after texture draw.
    ///   - commandBuffer: command buffer to put the work in.
    ///   - fence: metal fence.
    public func draw(texture: MTLTexture,
                     additionalRenderCommands: ((MTLRenderCommandEncoder) -> Void)? = nil,
                     in commandBuffer: MTLCommandBuffer,
                     fence: MTLFence? = nil) {
        guard let drawable = self.layer.nextDrawable()
        else { return }

        self.renderPassDescriptor.colorAttachments[0].texture = drawable.texture

        commandBuffer.render(descriptor: self.renderPassDescriptor) { renderEncoder in
            self.draw(texture: texture,
                      in: drawable,
                      additionalRenderCommands: additionalRenderCommands,
                      using: renderEncoder,
                      fence: fence)
        }

        commandBuffer.present(drawable)
    }

    private func draw(texture: MTLTexture,
                      in drawable: CAMetalDrawable,
                      additionalRenderCommands: ((MTLRenderCommandEncoder) -> Void)? = nil,
                      using renderEncoder: MTLRenderCommandEncoder,
                      fence: MTLFence? = nil) {
        if self.needsAdaptToTextureInput {
            self.recalculateProjectionMatrix(using: texture.size)
            self.needsAdaptToTextureInput = false
        }

        if let f = fence {
            renderEncoder.waitForFence(f, before: .fragment)
        }

        renderEncoder.setCullMode(.none)
        renderEncoder.setRenderPipelineState(self.renderPipelineState)
        
        renderEncoder.set(vertexValue: matrix_float4x4(self.projectionMatrix),
                          at: 0)

        renderEncoder.setFragmentTexture(texture,
                                         index: 0)

        renderEncoder.drawPrimitives(type: .triangleStrip,
                                     vertexStart: 0,
                                     vertexCount: 4)

        additionalRenderCommands?(renderEncoder)
    }

    // MARK - Pipeline State Init

    static func makeRenderState(for context: MTLContext,
                                pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState {
        do {
            let library = try context.library(for: Self.self)

            let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
            renderPipelineDescriptor.label = "PixelBufferPipeline"
            renderPipelineDescriptor.vertexFunction = library.makeFunction(name: Self.vertexFunctionName)
            renderPipelineDescriptor.fragmentFunction = library.makeFunction(name: Self.fragmentFunctionName)
            renderPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false

            return try context.renderPipelineState(descriptor: renderPipelineDescriptor)
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    static let vertexFunctionName = "vertexFunction"
    static let fragmentFunctionName = "fragmentFunction"
}
