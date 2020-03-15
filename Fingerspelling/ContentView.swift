import Combine
import SwiftUI

// MARK: Views

struct ContentView: View {
  @State private var answer: String = ""
  @State private var score = 0
  /// Timer used to delay playing the next word
  @State private var delayTimer: Timer? = nil
  @State private var isShowingSettings: Bool = false

  @EnvironmentObject private var playback: PlaybackService
  @EnvironmentObject private var feedback: FeedbackService

  @ObservedObject private var settings = UserSettings()
  @ObservedObject private var keyboard = KeyboardResponder()

  private static let minSpeed = 1.0
  private static let maxSpeed = 11.0
  private static let postSubmitDelay = 2.0 // seconds
  private static let nextWordDelay = 1.0 // seconds

  private var answerIsCorrect: Bool {
    self.answerTrimmed.lowercased() == self.playback.currentWord.lowercased()
  }

  private var answerTrimmed: String {
    self.answer.trimmingCharacters(in: .whitespaces)
  }

  var body: some View {
    VStack {
      GameStatusBar(
        score: self.score,
        speed: self.settings.speed,
        isShowingSettings: self.$isShowingSettings
      )
      Divider().padding(.bottom, 10)

      if self.feedback.hasCorrectAnswer || self.feedback.isRevealed {
        Text(self.playback.currentWord.uppercased())
          .font(.system(.title, design: .monospaced))
          .minimumScaleFactor(0.8)
          .scaledToFill()
      }

      HStack {
        AnswerInput(value: self.$answer, onSubmit: self.handleSubmit).modifier(SystemServices())
        if !self.feedback.shouldDisableControls {
          Spacer()
          Button(action: self.handleReveal) {
            Text("Reveal").font(.system(size: 14))
          }.disabled(self.playback.isPlaying)
        }
      }
      Spacer()
      MainDisplay().frame(width: 100, height: 150)
      Spacer()
      SpeedControl(
        value: self.$settings.speed,
        minSpeed: Self.minSpeed,
        maxSpeed: Self.maxSpeed,
        disabled: self.playback.isPlaying
      )
      .padding(.bottom, 10)
      PlaybackControl(onPlay: self.handlePlay, onStop: self.handleStop).padding(.bottom, 10)
    }
    // Move the current UI up when the keyboard is active
    .padding(.bottom, keyboard.currentHeight)
    .padding(.top, 10)
    .padding(.horizontal, 20)
  }

  private func playWord() {
    self.playback.play()
    self.feedback.hide()
  }

  // MARK: Handlers

  private func handlePlay() {
    self.playWord()
  }

  private func handleNextWord() {
    self.answer = ""
    self.playback.setNextWord()
    self.feedback.reset()

    self.delayTimer = delayFor(Self.nextWordDelay) {
      self.playWord()
    }
  }

  private func handleStop() {
    self.delayTimer?.invalidate()
    self.playback.stop()
    self.feedback.hide()
  }

  private func handleReveal() {
    self.playback.stop()
    self.feedback.reveal()
    delayFor(Self.postSubmitDelay) {
      self.feedback.hide()
      self.handleNextWord()
    }
  }

  private func handleSubmit() {
    // Prevent multiple submissions when pressing "return" key
    if self.feedback.hasCorrectAnswer {
      return
    }
    self.handleStop()
    self.feedback.show()
    if self.answerIsCorrect {
      self.feedback.markCorrect()
      self.score += 1
      delayFor(Self.postSubmitDelay) {
        self.handleNextWord()
      }
    } else {
      delayFor(0.5) {
        self.feedback.hide()
      }
    }
  }
}

struct GameStatusBar: View {
  var score: Int
  var speed: Double
  @Binding var isShowingSettings: Bool

  static let iconSize: CGFloat = 14

  var scoreDisplay: some View {
    HStack {
      Image(systemName: "checkmark").foregroundColor(.primary)
      Text(String(self.score)).font(.system(size: Self.iconSize)).bold()
    }
    .foregroundColor(Color.primary)
  }

  var speedDisplay: some View {
    HStack {
      Image(systemName: "metronome").foregroundColor(.primary)
      Text(String(Int(self.speed))).font(.system(size: Self.iconSize))
    }.padding(.horizontal, 10)
      .foregroundColor(Color.primary)
  }

  var settingsButton: some View {
    Button(action: { self.isShowingSettings.toggle() }) {
      Image(systemName: "gear")
    }
  }

  var body: some View {
    HStack {
      self.scoreDisplay
      self.speedDisplay
      Spacer()
      self.settingsButton
    }
    .sheet(isPresented: self.$isShowingSettings) {
      GameSettings(isPresented: self.$isShowingSettings)
    }
  }
}

struct GameSettings: View {
  @Binding var isPresented: Bool

  @ObservedObject private var settings = UserSettings()

  static let wordLengths = Array(3 ... 6) + [Int.max]

  var dismissButton: some View {
    Button(action: { self.isPresented = false }) {
      Text("Done")
    }
  }

  var body: some View {
    NavigationView {
      Form {
        Section(header: Text("Max word length".uppercased())) {
          Picker(selection: self.$settings.maxWordLength, label: Text("Max word length")) {
            ForEach(Self.wordLengths, id: \.self) {
              Text($0 == Int.max ? "Any" : "\($0) letters").tag($0)
            }
          }.pickerStyle(SegmentedPickerStyle())
        }
      }
      .navigationBarTitle(Text("Settings"), displayMode: .inline)
      .navigationBarItems(trailing: self.dismissButton)
    }
  }
}

struct AnswerInput: View {
  @Binding var value: String
  var onSubmit: () -> Void

  @EnvironmentObject var feedback: FeedbackService

  var body: some View {
    HStack {
      FocusableTextField(
        text: self.$value,
        isFirstResponder: true,
        placeholder: "WORD",
        textFieldShouldReturn: { _ in
          self.onSubmit()
          return true
        },
        modifyTextField: { textField in
          textField.borderStyle = .roundedRect
          textField.autocapitalizationType = .allCharacters
          textField.autocorrectionType = .no
          textField.returnKeyType = .done
          textField.keyboardType = .asciiCapable
          textField.font = .monospacedSystemFont(ofSize: 18.0, weight: .regular)
          textField.clearButtonMode = .whileEditing
          return textField
        }
      )
      // Hide input after success.
      // Note: we use opacity to hide because the text field needs to be present for the keyboard
      //   to remain on the screen and we set the frame to 0 to make room for the correct word display.
      .frame(width: self.feedback.shouldDisableControls ? 0 : 280, height: self.feedback.hasCorrectAnswer ? 0 : 30)
      .opacity(self.feedback.shouldDisableControls ? 0 : 1)
    }
  }
}

struct MainDisplay: View {
  @EnvironmentObject var playback: PlaybackService
  @EnvironmentObject var feedback: FeedbackService

  var body: some View {
    VStack {
      if !self.playback.isPlaying {
        if self.feedback.isShown || self.feedback.hasCorrectAnswer {
          FeedbackDisplay(isCorrect: self.feedback.hasCorrectAnswer)
        }
      } else {
        // Need to pass SystemServices due to a bug in SwiftUI
        //   re: environment not getting passed to children
        LetterDisplay().modifier(SystemServices())
      }
    }
  }
}

struct LetterDisplay: View {
  @EnvironmentObject var playback: PlaybackService

  var body: some View {
    // XXX: Complicated implementation of an animated image
    //   since there doesn't seem to be a better way to do this in
    //   SwiftUI yet: https://stackoverflow.com/a/57749621/1157536
    Image(uiImage: self.playback.currentLetterImage)
      .resizable()
      .frame(width: 225, height: 225)
      .scaledToFit()
      .offset(x: self.playback.currentLetterIsRepeat ? -20 : 0)
      .onReceive(
        self.playback.playTimer!.publisher,
        perform: { _ in
          self.playback.setNextLetter()
        }
      )
      .onAppear {
        self.playback.resetTimer()
        self.playback.startTimer()
      }
      .onDisappear {
        self.playback.resetTimer()
      }
  }
}

struct FeedbackDisplay: View {
  var isCorrect: Bool

  var body: some View {
    Group {
      if self.isCorrect {
        Image(systemName: "checkmark.circle")
          .modifier(MainDisplayIcon())
          .foregroundColor(Color.green)
      } else {
        Image(systemName: "xmark.circle")
          .modifier(MainDisplayIcon())
          .foregroundColor(Color.red)
      }
    }
  }
}

struct SpeedControl: View {
  @Binding var value: Double

  var minSpeed: Double
  var maxSpeed: Double
  var disabled: Bool

  var body: some View {
    HStack {
      Image(systemName: "tortoise").foregroundColor(.gray)
      Slider(value: self.$value, in: self.minSpeed ... self.maxSpeed, step: 1)
        .disabled(self.disabled)
      Image(systemName: "hare").foregroundColor(.gray)
    }
  }
}

struct PlaybackControl: View {
  var onPlay: () -> Void
  var onStop: () -> Void

  @EnvironmentObject var playback: PlaybackService
  @EnvironmentObject var feedback: FeedbackService

  var body: some View {
    HStack {
      if !self.playback.isActive {
        Button(action: self.onPlay) {
          Image(systemName: "play.fill")
            .font(.system(size: 18))
            .modifier(FullWidthButtonContent(disabled: self.feedback.shouldDisableControls))
        }.disabled(self.feedback.shouldDisableControls)
      } else {
        Button(action: self.onStop) {
          Image(systemName: "stop.fill")
            .font(.system(size: 18))
            .modifier(FullWidthGhostButtonContent())
        }
      }
    }
  }
}

// MARK: State/service objects

// https://medium.com/better-programming/swiftui-microservices-c7002228710

final class PlaybackService: ObservableObject {
  @Published var currentWord = getRandomWord()
  @Published var letterIndex = 0
  @Published var isPlaying = false
  @Published var playTimer: LoadingTimer?
  @Published var isPendingNextWord: Bool = false

  @ObservedObject var settings = UserSettings()

  private static let numerator = 2.0 // Higher value = slower speeds

  init() {
    self.playTimer = self.getTimer()
  }

  var currentLetterImage: UIImage {
    self.images[self.letterIndex]
  }

  var currentLetterIsRepeat: Bool {
    self.letterIndex > 0 &&
      Array(self.currentWord)[self.letterIndex - 1] == Array(self.currentWord)[self.letterIndex]
  }

  var isActive: Bool {
    self.isPlaying || self.isPendingNextWord
  }

  private var images: [UIImage] {
    let letters = Array(self.currentWord).map { "\(String($0).uppercased())-lauren-nobg" }
    return letters.map { UIImage(named: $0)! }
  }

  func play() {
    self.letterIndex = 0
    self.isPlaying = true
    self.isPendingNextWord = false
  }

  func stop() {
    self.resetTimer()
    self.play()
    self.isPlaying = false
    self.isPendingNextWord = false
  }

  func setNextLetter() {
    if self.letterIndex >= (self.images.count - 1) {
      self.isPlaying = false
    } else {
      self.letterIndex += 1
    }
  }

  func setNextWord() {
    self.currentWord = getRandomWord()
    self.isPendingNextWord = true
  }

  func startTimer() {
    self.playTimer!.start()
  }

  func resetTimer() {
    self.playTimer!.cancel()
    self.playTimer = self.getTimer()
  }

  private func getTimer() -> LoadingTimer {
    let every = Self.numerator / self.settings.speed
    return LoadingTimer(every: every)
  }
}

final class FeedbackService: ObservableObject {
  @Published var isShown: Bool = false
  @Published var hasCorrectAnswer: Bool = false
  @Published var isRevealed: Bool = false

  var shouldDisableControls: Bool {
    self.hasCorrectAnswer || self.isRevealed
  }

  func show() {
    self.isShown = true
  }

  func hide() {
    self.isShown = false
    self.isRevealed = false
  }

  func reveal() {
    self.isRevealed = true
    self.isShown = false
  }

  func markCorrect() {
    self.hasCorrectAnswer = true
  }

  func reset() {
    self.hasCorrectAnswer = false
    self.isShown = false
  }
}

// MARK: ViewModifiers

// https://medium.com/swlh/swiftui-and-the-missing-environment-object-1a4bf8913ba7
struct SystemServices: ViewModifier {
  static var playback = PlaybackService()
  static var feedback = FeedbackService()

  func body(content: Content) -> some View {
    content
      .environmentObject(Self.playback)
      .environmentObject(Self.feedback)
  }
}

struct IconButton: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding()
      .font(.system(size: 24))
  }
}

struct MainDisplayIcon: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding()
      .font(.system(size: 120))
  }
}

struct FullWidthButtonContent: ViewModifier {
  var background: Color = Color.blue
  var foregroundColor: Color = Color.white
  var disabled: Bool = false

  func body(content: Content) -> some View {
    content
      .frame(minWidth: 0, maxWidth: .infinity)
      .padding()
      .background(self.background)
      .foregroundColor(self.foregroundColor)
      .cornerRadius(40)
      .opacity(self.disabled ? 0.5 : 1)
  }
}

struct FullWidthGhostButtonContent: ViewModifier {
  var color: Color = Color.blue

  func body(content: Content) -> some View {
    content
      .frame(minWidth: 0, maxWidth: .infinity)
      .padding()
      .overlay(
        RoundedRectangle(cornerRadius: 40)
          .stroke(self.color, lineWidth: 1)
      )
      .foregroundColor(self.color)
  }
}

// MARK: Utilities

private func getRandomWord() -> String {
  let word = Words.randomElement()!
  print("current word: " + word)
  return word
}

class LoadingTimer {
  var publisher: Timer.TimerPublisher
  private var timerCancellable: Cancellable?

  init(every: Double) {
    self.publisher = Timer.publish(every: every, on: .main, in: .default)
    self.timerCancellable = nil
  }

  func start() {
    self.timerCancellable = self.publisher.connect()
  }

  func cancel() {
    self.timerCancellable?.cancel()
  }
}

@discardableResult
func delayFor(_ seconds: Double, onComplete: @escaping () -> Void) -> Timer {
  Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
    onComplete()
  }
}

// MARK: Preview

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    let playback = SystemServices.playback
    let feedback = SystemServices.feedback

    // Modify these during development to update the preview
    playback.isPlaying = true
    playback.currentWord = "foo"
    feedback.isShown = false

    return ContentView().modifier(SystemServices())
  }
}
