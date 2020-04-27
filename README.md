# EasyPlay

Makes it easy to play videos.

```swift
let player = try! Player(videoSource: .camera(position: .back))
player.play { pixelBuffer in
    // uses `pixelBuffer` here
}

// ...

player.pause()
```
