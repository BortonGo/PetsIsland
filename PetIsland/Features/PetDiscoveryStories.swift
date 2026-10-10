import SwiftUI

extension PetDiscoveryMemory {
    var storyText: String {
        let name = pet.name
        switch (discovery, story ?? .original) {
        case (_, .original): return discovery.discoveryStory(petName: name)
        case (.stripedPebble, .curious): return String(localized: "\(name) followed a stripe in the path and found it continued across a pebble. A very small map, with home at the end.")
        case (.stripedPebble, .quiet): return String(localized: "\(name) chose a pebble warmed by the sun. Perhaps a little of that warmth will stay in your pocket.")
        case (.clover, .curious): return String(localized: "\(name) watched a beetle disappear beneath a clover leaf. The beetle kept its hiding place; you get the lucky leaf.")
        case (.clover, .quiet): return String(localized: "\(name) rested beside a patch of clover until the breeze settled. This leaf is a reminder that there is no need to hurry.")
        case (.tinyFlower, .curious): return String(localized: "\(name) almost walked past a flower growing through a crack. Even the path has a secret garden.")
        case (.tinyFlower, .quiet): return String(localized: "\(name) found a fallen flower beside a sunny bench. It seemed too lovely to leave without a place in your album.")
        case (.ribbon, .curious): return String(localized: "\(name) followed a ribbon fluttering on a low twig. It looks like the garden tried to wrap itself as a present.")
        case (.ribbon, .quiet): return String(localized: "\(name) brought a ribbon from the quiet end of the path. A bookmark for a day you might want to remember.")
        case (.shell, .curious): return String(localized: "\(name) found a shell hiding in a tiny pool. The tide left a little treasure chest with nothing to unlock.")
        case (.shell, .quiet): return String(localized: "\(name) waited for a wave to retreat before choosing this shell. It carries a little pause between two waves.")
        case (.seaGlass, .curious): return String(localized: "\(name) spotted a flash between the pebbles. It was not a star after all, but it can still brighten your album.")
        case (.seaGlass, .quiet): return String(localized: "\(name) held a smooth piece of sea glass up to the light. For a moment, the whole shore had its colour.")
        case (.driftwood, .curious): return String(localized: "\(name) found a twig shaped like a question mark. Where has it sailed? The sea is keeping that story to itself.")
        case (.driftwood, .quiet): return String(localized: "\(name) sat beside a piece of driftwood and watched the water. It has travelled enough; your island can be its home now.")
        case (.smoothStone, .curious): return String(localized: "\(name) sorted through pebbles until one rolled in a perfect circle. This one would win a very quiet race.")
        case (.smoothStone, .quiet): return String(localized: "\(name) found a stone beside a line of sea foam. A small reminder of a wave that has already gone.")
        case (.feather, .curious): return String(localized: "\(name) followed a feather caught in a slow swirl of air. The forest was playing catch without making a sound.")
        case (.feather, .quiet): return String(localized: "\(name) found a feather resting on the moss. Some gifts arrive so softly that nobody hears them.")
        case (.pinecone, .curious): return String(localized: "\(name) found a pinecone balanced on a root like a little tower. It stayed standing all the way to your album.")
        case (.pinecone, .quiet): return String(localized: "\(name) chose a pinecone from a warm patch of forest floor. It brings a little woodland afternoon home with it.")
        case (.acorn, .curious): return String(localized: "\(name) found an acorn tucked into a hollow root. Someone started a tiny pantry and forgot the address.")
        case (.acorn, .quiet): return String(localized: "\(name) paused under the trees with an acorn nearby. It is a small thing with a very patient plan to become a tree.")
        case (.mapleLeaf, .curious): return String(localized: "\(name) followed a leaf spinning down the path. One last dance, then a place in your collection.")
        case (.mapleLeaf, .quiet): return String(localized: "\(name) found a bright leaf on the shadowy path. A little window of autumn light to keep for another day.")
        }
    }

    var shareText: String { "\(discovery.discoveryTitle)\n\(storyText)" }
}

extension PetWalkStory {
    var title: String {
        switch self {
        case .original: String(localized: "A small surprise")
        case .curious: String(localized: "A curious detour")
        case .quiet: String(localized: "A quiet discovery")
        }
    }

    func note(on route: PetWalkRoute, chapter: PetWalkChapter) -> String {
        let notes: [String]
        switch (route, self) {
        case (.garden, .original):
            notes = [
                String(localized: "The garden gate is behind us. There is a sunny patch just ahead."),
                String(localized: "Something rustles in the flower bed. A short pause to look closer."),
                String(localized: "There is a small surprise to bring home. The garden knows how to give presents."),
            ]
        case (.garden, .curious):
            notes = [
                String(localized: "A beetle crosses the path as if it knows a secret shortcut."),
                String(localized: "A low branch shakes in the breeze. There is something interesting underneath."),
                String(localized: "The detour was worth it. A tiny keepsake is coming back with us."),
            ]
        case (.garden, .quiet):
            notes = [
                String(localized: "The quiet side of the garden smells of grass and warm earth."),
                String(localized: "A little rest beside the bench. The flowers sway without any hurry."),
                String(localized: "One small thing will help remember this peaceful corner."),
            ]
        case (.shore, .original):
            notes = [
                String(localized: "The sand is soft here. Little waves draw lines along the beach."),
                String(localized: "The water retreats, leaving a fresh row of pebbles to inspect."),
                String(localized: "The shore has left something small enough to take home."),
            ]
        case (.shore, .curious):
            notes = [
                String(localized: "A trail of bubbles leads towards the reeds. It looks worth following."),
                String(localized: "There is a glint where a wave has just passed. Time for a closer look."),
                String(localized: "A little beach mystery is solved. Its souvenir can travel home."),
            ]
        case (.shore, .quiet):
            notes = [
                String(localized: "The waves make an unhurried rhythm. There is plenty of time to listen."),
                String(localized: "A sheltered patch beside the reeds makes a lovely resting place."),
                String(localized: "A small keepsake will carry a little of this calm back to the island."),
            ]
        case (.grove, .original):
            notes = [
                String(localized: "The trees make a cool arch over the path. A woodland walk begins."),
                String(localized: "There is a soft rustle near the roots. The ground has little secrets too."),
                String(localized: "Something from this woodland corner is ready for the album."),
            ]
        case (.grove, .curious):
            notes = [
                String(localized: "A winding root looks almost like an arrow pointing into the grove."),
                String(localized: "Behind the fallen log, a patch of moss hides a tiny surprise."),
                String(localized: "A small discovery makes the winding path worth remembering."),
            ]
        case (.grove, .quiet):
            notes = [
                String(localized: "Light filters between the leaves. The grove feels especially quiet."),
                String(localized: "A pause beside the mossy log. Even the leaves seem to whisper."),
                String(localized: "A little piece of the grove will keep this calm moment in the album."),
            ]
        }
        return notes[chapter.rawValue]
    }
}

extension PetWalkChapter {
    var title: String {
        switch self {
        case .settingOut: String(localized: "First steps")
        case .exploring: String(localized: "A little pause")
        case .homeward: String(localized: "A surprise for home")
        }
    }
}

struct PetWalkJournal: View {
    let route: PetWalkRoute
    let story: PetWalkStory
    let chapters: [PetWalkChapter]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(chapters) { chapter in
                VStack(alignment: .leading, spacing: 5) {
                    Label(chapter.title, systemImage: "leaf")
                        .font(.caption.weight(.semibold)).foregroundStyle(PetDesign.secondary)
                    Text(story.note(on: route, chapter: chapter))
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("discoveries.chapter.\(chapter.rawValue)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
