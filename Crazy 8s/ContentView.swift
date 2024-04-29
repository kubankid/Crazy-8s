import SwiftUI

enum Suit: String, CaseIterable {
    case hearts, diamonds, clubs, spades
}

enum Rank: Int, CaseIterable {
    case two = 2, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace
}

struct Card: Identifiable {
    var id = UUID()
    var rank: Rank
    var suit: Suit
    
    var imageName: String {
        "\(rank)_of_\(suit)".lowercased()
    }
}

struct Deck {
    private(set) var cards: [Card] = []

    init() {
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                cards.append(Card(rank: rank, suit: suit))
            }
        }
        shuffle()
    }

    mutating func shuffle() {
        cards.shuffle()
    }

    mutating func draw() -> Card? {
        if cards.isEmpty { return nil }
        return cards.removeFirst()
    }
}

class Game: ObservableObject {
    @Published var deck = Deck()
    @Published var currentPlayerHand: [Card] = []
    @Published var currentCard: Card?
    @Published var opponentHand: [Card] = []
    @Published var isPlayerTurn: Bool = true
    @Published var winner: String?
    @Published var pickupCards: Int = 0
    @Published var showEndGameAlert = false
    @Published var gameMessage = ""
    @Published var showSuitPicker = false
    @Published var currentSuit: Suit?
    @Published var opponentSuitChangeMessage: String = ""

    init() {
        startNewGame()
    }

    func startNewGame() {
        deck.shuffle()
        currentPlayerHand = (1...8).compactMap { _ in deck.draw() }
        opponentHand = (1...8).compactMap { _ in deck.draw() }
        currentCard = deck.draw()
        isPlayerTurn = Bool.random()
    }

    func playCards(cards: [Card]) {
        guard !cards.isEmpty, let currentCard = currentCard, cards.first!.suit == currentCard.suit || cards.first!.rank == currentCard.rank || cards.contains(where: { $0.rank == .eight }) else {
            return
        }

        for card in cards {
            currentPlayerHand.removeAll { $0.id == card.id }
        }
        self.currentCard = cards.last
        applyCardEffects(cards.last!)
        if cards.last?.rank != .four && cards.last?.rank != .ace {
            endTurn()
        }
    }

    func drawCard() {
        let cardsToPickup = max(1, pickupCards)
        for _ in 0..<cardsToPickup {
            if let newCard = deck.draw() {
                currentPlayerHand.append(newCard)
            }
        }
        pickupCards = 0
        endTurn()
    }

    func applyCardEffects(_ card: Card) {
        switch card.rank {
        case .two:
            pickupCards += 2
        case .four, .ace:
            // Skip the next turn.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isPlayerTurn.toggle()  // This effectively skips the next player's turn.
            }
        case .queen where card.suit == .spades:
            pickupCards += 5
        case .eight:
            // Trigger suit change without affecting turn logic here.
            if !isPlayerTurn {  // If CPU plays an eight, automatically choose a suit.
                let randomSuit = Suit.allCases.randomElement()!
                changeSuit(to: randomSuit)
                opponentSuitChangeMessage = "Opponent changed suit to \(randomSuit.rawValue.capitalized)."
            } else {
                showSuitPicker = true  // Show suit picker for the player.
            }
        default:
            break
        }
    }

    func changeSuit(to suit: Suit) {
        currentSuit = suit
        showSuitPicker = false
        // Do not toggle the turn here; let the endTurn method handle it.
    }

    func endTurn() {
        if !(currentCard?.rank == .four || currentCard?.rank == .ace || currentCard?.rank == .eight) {
            isPlayerTurn.toggle()
        }
        checkForWinner()
        if !isPlayerTurn {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.opponentPlayCard()
            }
        }
    }


    func opponentPlayCard() {
        if pickupCards > 0 {
            opponentPickupCards()
        } else if let playableCard = opponentHand.first(where: { canPlay(card: $0, onTopOf: currentCard!) }) {
            playCardByOpponent(card: playableCard)
        } else {
            drawCardForOpponent()
        }
    }

    func playCardByOpponent(card: Card) {
        opponentHand.removeAll { $0.id == card.id }
        currentCard = card
        applyCardEffects(card)
        endTurn()
    }

    func drawCardForOpponent() {
        if let newCard = deck.draw() {
            opponentHand.append(newCard)
        }
        endTurn()
    }

    func opponentPickupCards() {
        let cardsToPickup = max(1, pickupCards)
        for _ in 0..<cardsToPickup {
            if let newCard = deck.draw() {
                opponentHand.append(newCard)
            }
        }
        pickupCards = 0
        isPlayerTurn = true  // Hand back control to the player
    }

    func checkForWinner() {
        if currentPlayerHand.isEmpty {
            gameMessage = "Player wins!"
            showEndGameAlert = true
        } else if opponentHand.isEmpty {
            gameMessage = "Opponent wins!"
            showEndGameAlert = true
        }
    }

    func canPlay(card: Card, onTopOf topCard: Card) -> Bool {
        return card.suit == topCard.suit || card.rank == topCard.rank || card.rank == .eight || (pickupCards > 0 && card.rank == .two)
    }
}

struct CardView: View {
    let card: Card
    var isFaceUp: Bool
    
    var body: some View {
        Image(isFaceUp ? card.imageName : "card_back")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .cornerRadius(10)
            .shadow(radius: 5)
            .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 1), value: isFaceUp)
    }
}

struct GameView: View {
    @ObservedObject var game: Game
    @State private var selectedCards: [Card] = []

    var body: some View {
        VStack {
            Text("Opponent has \(game.opponentHand.count) cards")
                .font(.headline)
                .padding(.top)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack {
                    ForEach(game.opponentHand.indices, id: \.self) { index in
                        CardView(card: game.opponentHand[index], isFaceUp: false)
                            .frame(width: 60, height: 90)
                            .padding(4)
                    }
                }
            }
            .padding(.top)
            
            Spacer()
            
            if let currentCard = game.currentCard {
                CardView(card: currentCard, isFaceUp: true)
                    .frame(width: 125, height: 175)
                    .padding()
            }
            
            Spacer()
            
            Text("You have \(game.currentPlayerHand.count) cards")
                .font(.headline)
                .padding(.bottom)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack {
                    ForEach(game.currentPlayerHand) { card in
                        CardView(card: card, isFaceUp: true)
                            .frame(width: 60, height: 90)
                            .padding(4)
                            .border(selectedCards.contains(where: { $0.id == card.id }) ? Color.blue : Color.clear, width: 3)
                            .onTapGesture {
                                if selectedCards.contains(where: { $0.id == card.id }) {
                                    selectedCards.removeAll { $0.id == card.id }
                                } else {
                                    selectedCards.append(card)
                                }
                            }
                    }
                }
            }
            .padding(.bottom)
            
            HStack {
                Button("Pick Up Card") {
                    withAnimation {
                        game.drawCard()
                    }
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                
                Button("Play Selected Cards") {
                    withAnimation {
                        game.playCards(cards: selectedCards)
                        selectedCards.removeAll()
                    }
                }
                .disabled(selectedCards.isEmpty)
                .padding()
                .background(selectedCards.isEmpty ? Color.gray : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .actionSheet(isPresented: $game.showSuitPicker) {
            ActionSheet(title: Text("Choose a new suit"), message: nil, buttons: [
                .default(Text("Hearts")) { game.changeSuit(to: .hearts) },
                .default(Text("Diamonds")) { game.changeSuit(to: .diamonds) },
                .default(Text("Clubs")) { game.changeSuit(to: .clubs) },
                .default(Text("Spades")) { game.changeSuit(to: .spades) },
                .cancel()
            ])
        }
        .alert(isPresented: $game.showEndGameAlert) {
            Alert(title: Text("Game Over"), message: Text(game.gameMessage), primaryButton: .default(Text("Play Again")) {
                game.startNewGame()
            }, secondaryButton: .cancel())
        }
    }
}

struct MenuView: View {
    var body: some View {
        NavigationView {
            VStack {
                NavigationLink(destination: GameView(game: Game())) {
                    Text("Single Player")
                }
                Text("Multiplayer (Coming Soon)")
            }
        }
    }
}

@main
struct Crazy8sApp: App {
    var body: some Scene {
        WindowGroup {
            MenuView()
        }
    }
}
