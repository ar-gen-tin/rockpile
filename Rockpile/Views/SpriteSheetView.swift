import SwiftUI

struct SpriteSheetView: View {
    let spriteSheet: String
    var frameCount: Int = 6
    var columns: Int = 6
    var fps: Double = 10
    var isAnimating: Bool = true
    /// Optional Aseprite JSON metadata — when provided, uses exact frame rects and per-frame durations
    var metadata: SpriteMetadata?

    var body: some View {
        let effectiveFPS = metadata?.fps ?? fps
        let effectiveFrameCount = metadata?.frameCount ?? frameCount

        TimelineView(.animation(minimumInterval: 1.0 / effectiveFPS, paused: !isAnimating)) { timeline in
            if let metadata = metadata {
                MetadataSpriteFrameView(
                    spriteSheet: spriteSheet,
                    metadata: metadata,
                    currentFrame: currentFrame(at: timeline.date, frameCount: effectiveFrameCount, fps: effectiveFPS)
                )
            } else {
                SpriteFrameView(
                    spriteSheet: spriteSheet,
                    frameCount: frameCount,
                    columns: columns,
                    currentFrame: currentFrame(at: timeline.date, frameCount: frameCount, fps: fps)
                )
            }
        }
    }

    private func currentFrame(at date: Date, frameCount: Int, fps: Double) -> Int {
        guard isAnimating else { return 0 }
        let elapsed = date.timeIntervalSinceReferenceDate
        return Int(elapsed * fps) % frameCount
    }
}

/// Grid-based frame rendering (existing behavior)
private struct SpriteFrameView: View {
    let spriteSheet: String
    let frameCount: Int
    let columns: Int
    let currentFrame: Int

    var body: some View {
        GeometryReader { geometry in
            let frameWidth = geometry.size.width
            let frameHeight = geometry.size.height
            let rows = (frameCount + columns - 1) / columns

            let col = currentFrame % columns
            let row = currentFrame / columns

            Image(spriteSheet)
                .renderingMode(.original)
                .interpolation(.none)
                .resizable()
                .frame(width: frameWidth * CGFloat(columns),
                       height: frameHeight * CGFloat(rows))
                .offset(x: -frameWidth * CGFloat(col),
                        y: -frameHeight * CGFloat(row))
        }
        .clipped()
    }
}

/// Aseprite JSON metadata-driven frame rendering (packed sprite sheets)
private struct MetadataSpriteFrameView: View {
    let spriteSheet: String
    let metadata: SpriteMetadata
    let currentFrame: Int

    var body: some View {
        GeometryReader { geometry in
            if let rect = metadata.frameRect(at: currentFrame),
               let sheetSize = metadata.meta.size {
                let scaleX = geometry.size.width / CGFloat(rect.w)
                let scaleY = geometry.size.height / CGFloat(rect.h)

                Image(spriteSheet)
                    .renderingMode(.original)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: CGFloat(sheetSize.w) * scaleX,
                           height: CGFloat(sheetSize.h) * scaleY)
                    .offset(x: -CGFloat(rect.x) * scaleX,
                            y: -CGFloat(rect.y) * scaleY)
            }
        }
        .clipped()
    }
}
