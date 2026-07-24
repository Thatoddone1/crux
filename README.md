#  Crux

Crux is a Matrix client for iOS, built to get you to the most important messages as quick as possible. 

It is built in native Swift and SwiftUI with the Matrix-Rust-SDK. It's core feature is the Mountain (better names welcome :)), a stack of cards, each for an unread conversation. These cards are then sorted into three piles: A "crux" pile with the most important messages, a "slope" pile with less imporant messages, and a muted pile with rooms set to "muted". Within these piles, cards are further sorted. All sorting is done using deails about the room; this includes favorite status, low-priority status, mentions, if it is a DM, opt-in local AI (coming soon?), amoung other characteristic. Of course, all these parameters can be tuned in the settings. In addition to the "Mountain", you can access all rooms and spaces, in addition to invites, in their own tabs. 

The goal of Crux is simple: Get it to be so quick at surfacing important messages that people don't have to spend a lot of time in the app. You should open the app and instantly see which important new messages, as defined by you, are there. All while simultaniously being a good Matrix client for participating in and creating new conversations.


> [!WARNING] 
> Crux is not nearly feature complete, or even remotely stable yet. It is still in Alpha, if you can even call it that. I am trying to work on this project whenever I can, so hopefully it is at least brought to a minimal viable product sometime soon. Contributions are certainly welcome, but keep in mind the work in progress that this is! Thanks for giving this project a look


## Development and Contribution

Firstly, I would like to thank those who worked on the MatrixRustSDK, and the bindings for Swift. It is really a phenominal library. It is licenced under Apache 2.0, avaliable [here](https://www.apache.org/licenses/LICENSE-2.0).

Through the MatrixService object, most of the library is abstracted, with simple function calls used by the views themselves. The user session is represented by UserSession, containing the RoomListModel. Each Room has a TimelineModel containg the events and messages (each with their own structs). This means that I don't have to call the library itself in the views, making it all a lot more portable. Please try your best to keep this structure and not introduce too much logic to the view when contributing. It is not full MVVM, but borrows aspects. 

Users sessions themselves are stored on disk by the library, with credentials in the Keychain. It is autoloaded in if found on each boot.

### AI Policy
You are more than welcome to use Generative Artificial Intelignce tools to contribute. I'll be honest, I used them to help create the foundation of the app, and some of the backend stuff. The one thing that I please implore you to do: Read over any and all code genereated by and it and make sure you understand and, crucially, **agree with it** before you try and submit anything. While modern AI tools are incrediably powerful, they are not perfect and often write unscalable or messy code, full of lengthy and useless comments, often with UI that doesn't even make sense from a user's perspective. So I ask you just be careful. Thank you!
