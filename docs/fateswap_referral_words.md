# FateSwap — Referral Code Word Lists

> **Format**: `{adjective}-{participle}-{animal}` (e.g., `rekt-hodling-walrus`)
> **Combinations**: 40 × 40 × 171 = **273,600** unique codes
> **Rules**: All words 1-3 syllables, easy to spell verbally, no offensive words, crypto/trading/degen themed

---

## List 1: Adjectives (40 words)

Crypto, trading, degen — every adjective has trading floor or CT energy.

```elixir
@adjectives ~w(
  alpha based bearish bold broke bullish cooked degen diamond doxxed
  dumped flipped fried giga greedy hyped jacked janky juiced leveraged
  margin mid minted moonlit onchain paperhands pegged pumped racked
  rekt risky rogue safu salty savage short tanked turbo volatile whale
)
```

**Count: 40**

## List 2: Participles (40 words)

Crypto/gambling verbs + absurd physical actions that make funny animal pairings.

```elixir
@participles ~w(
  aping bagholding betting bluffing bridging buying cashing dipping dumping
  farming flipping fomoing forking fudding gambling grinding hedging hodling
  larping leveraging longing minting pumping punting rugging scalping scheming
  selling shilling shorting sniping squeezing stacking staking swapping trading
  sweating tweeting vaulting yielding
)
```

**Count: 40**

## List 3: Animals (171 words)

Mix of common, exotic, and fun — easy to spell, easy to picture.

```elixir
@animals ~w(
  alpaca ape badger bat bear beaver beetle bison bobcat buffalo
  bull bunny camel cat cheetah chicken chimp clam cobra condor
  corgi cougar cow coyote crab crane cricket crow deer dingo
  dog dolphin donkey dove dragon duck eagle eel elk emu
  falcon ferret finch fish flamingo fox frog gator gecko gibbon
  giraffe goat goose gorilla grizzly guppy hamster hare hawk hedgehog
  heron hippo hornet horse hound husky hyena iguana impala jackal
  jaguar jellyfish kangaroo kiwi koala lemur leopard lion lizard llama
  lobster lynx macaw magpie mantis marmot meerkat mink mole monkey
  moose moth mouse mule narwhal newt ocelot octopus orca osprey
  ostrich otter owl ox panda panther parrot peacock pelican penguin
  pheasant pig pigeon pike piranha platypus pony poodle porcupine possum
  puffin puma python quail rabbit raccoon raven rhino robin rooster
  salmon sardine scorpion seal shark sheep shrimp skunk sloth slug
  snail snake sparrow spider squid stag stingray stork swan tapir
  tiger toad toucan trout tuna turkey turtle urchin viper vulture
  walrus warthog wasp weasel whale whelk wolf wombat wren yak
  zebra
)
```

---

## Generation Logic

```elixir
defmodule FateSwap.Referrals.CodeGenerator do
  @adjectives ~w(alpha based bearish ...)   # full list above
  @participles ~w(aping bagholding betting ...)
  @animals ~w(alpaca badger bat ...)

  @doc """
  Generate a unique three-word referral code.
  Format: adjective-participle-animal (e.g., "rekt-hodling-walrus")
  Retries on collision (rare with 273k combinations).
  """
  def generate do
    code = "#{Enum.random(@adjectives)}-#{Enum.random(@participles)}-#{Enum.random(@animals)}"

    if FateSwap.Referrals.code_taken?(code) do
      generate()  # Collision — re-roll (vanishingly rare)
    else
      code
    end
  end
end
```

## Validation Regex

```elixir
# Three lowercase words separated by hyphens
~r/^[a-z]+-[a-z]+-[a-z]+$/
```

```javascript
// JavaScript (client-side capture)
const threeWordRegex = /^[a-z]+-[a-z]+-[a-z]+$/;
```
