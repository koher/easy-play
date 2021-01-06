# EasyPlay

Makes it easy to capture frames from cameras and videos.

```swift
let player = try! Player(videoSource: .camera(position: .back))
player.play { frame in
    usePixelBuffer(frame.pixelBuffer)
}

// ...

player.pause()
```

## License

MIT
