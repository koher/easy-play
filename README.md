# EasyPlay

Makes it easy to capture frames from cameras and videos.

```swift
let camera = Camera(videoSource: .camera(position: .back))
let player = try! camera.player()
player.play { frame in
    usePixelBuffer(frame.pixelBuffer)
}

// ...

player.pause()
```

## License

MIT
