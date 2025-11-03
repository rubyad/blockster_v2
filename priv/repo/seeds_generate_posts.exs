# Script to generate 10 posts per category with similar format to the MoonPay article
# Run with: mix run priv/repo/seeds_generate_posts.exs

alias BlocksterV2.Repo
alias BlocksterV2.Blog
alias BlocksterV2.Blog.{Post, Category, Tag}
alias BlocksterV2.Accounts.User

# Get or create Adam Todd user
author = case Repo.get_by(User, email: "adam.todd@blockster.com") do
  nil ->
    {:ok, user} = %User{}
    |> User.changeset(%{
      email: "adam.todd@blockster.com",
      username: "Adam Todd",
      auth_method: "email",
      is_author: true
    })
    |> Repo.insert()
    user
  user -> user
end

IO.puts("Using author: #{author.email} (ID: #{author.id})")

# Get all categories
categories = Repo.all(Category)
IO.puts("\nFound #{length(categories)} categories")

# Get all tags
all_tags = Repo.all(Tag)
IO.puts("Found #{length(all_tags)} tags")

# Available images from priv/static/images
images = [
  "/images/bitcoin-guru.png",
  "/images/crypto-bull.png",
  "/images/ethereum.png",
  "/images/doge-coin.png",
  "/images/moonpay.png",
  "/images/w3-1.png",
  "/images/w3-2.png",
  "/images/w3-3.png",
  "/images/lifestyle-2.png",
  "/images/lifestyle-4.png"
]

# Sample tweet IDs for embedding
tweet_ids = [
  "20",  # Jack Dorsey's first tweet
  "1983911738891173992",  # MoonPay tweet
  "1234567890123456789",  # Fictional
  "1111111111111111111",  # Fictional
  "2222222222222222222"   # Fictional
]

# Function to generate Quill content similar to MoonPay article
defmodule ContentGenerator do
  def generate_content(title, category_name, author_name \\ "Adam Todd") do
    company = generate_company_name()
    partner = generate_partner_name()
    ceo_name = generate_ceo_name()
    quote = generate_quote(company)
    tweet_id = Enum.random(["20", "1983911738891173992", "1234567890123456789"])

    %{
      "ops" => [
        # Italic intro paragraph
        %{
          "attributes" => %{"italic" => true},
          "insert" => "#{generate_location()} — #{generate_intro(company, partner, category_name)}"
        },
        %{"insert" => "\n\n"},

        # Spacer
        %{"insert" => %{"spacer" => true}},

        # Main content with blockquote
        %{
          "insert" => "\n\n#{generate_body_paragraph_1(company, partner, category_name)}\n \n#{generate_body_paragraph_2(company)}\n\n\\"#{quote}\\""
        },
        %{"attributes" => %{"blockquote" => true}, "insert" => "\\n"},
        %{"insert" => "#{ceo_name}, CEO of #{company}"},
        %{"attributes" => %{"blockquote" => true}, "insert" => "\\n"},

        # Header 2
        %{"insert" => "\nWhat This Means"},
        %{"attributes" => %{"header" => 2}, "insert" => "\n"},

        # Bullet list
        %{"insert" => " \nWith this innovation, users can:\n \n#{generate_bullet_1(category_name)}"},
        %{"attributes" => %{"list" => "bullet"}, "insert" => "\n"},
        %{"insert" => "#{generate_bullet_2()}"},
        %{"attributes" => %{"list" => "bullet"}, "insert" => "\n"},
        %{"insert" => "#{generate_bullet_3()}"},
        %{"attributes" => %{"list" => "bullet"}, "insert" => "\n"},
        %{"insert" => "#{generate_bullet_4()}"},
        %{"attributes" => %{"list" => "bullet"}, "insert" => "\n"},
        %{"insert" => "#{generate_bullet_5()}"},
        %{"attributes" => %{"list" => "bullet"}, "insert" => "\n"},

        # Conclusion paragraph
        %{"insert" => "\n#{generate_conclusion(company, partner)}\n"},

        # Embedded tweet
        %{
          "insert" => %{
            "tweet" => %{
              "id" => tweet_id,
              "url" => "https://x.com/twitter/status/#{tweet_id}"
            }
          }
        },
        %{"insert" => "\n"},

        # Another header
        %{"insert" => "Why It Matters"},
        %{"attributes" => %{"header" => 2}, "insert" => "\n"},

        # Final paragraphs
        %{"insert" => " \n#{generate_why_matters(company, category_name)}\n \n\\"#{generate_final_quote()}\\""},
        %{"attributes" => %{"blockquote" => true}, "insert" => "\\n"},
        %{"insert" => "#{author_name}, Industry Analyst"},
        %{"attributes" => %{"blockquote" => true}, "insert" => "\\n"},

        # Technical details header
        %{"insert" => "\nTechnical Details"},
        %{"attributes" => %{"header" => 2}, "insert" => "\n"},

        # Final technical paragraph
        %{"insert" => " \n#{generate_technical_details(company, partner, category_name)}\n"}
      ]
    }
  end

  def generate_company_name do
    prefixes = ["Crypto", "Block", "Meta", "Quantum", "Stellar", "Nova", "Apex", "Prime"]
    suffixes = ["Labs", "Tech", "Finance", "Protocol", "Network", "Chain", "Ventures", "Global"]
    "#{Enum.random(prefixes)}#{Enum.random(suffixes)}"
  end

  def generate_partner_name do
    partners = ["Chainlink", "Polygon", "Avalanche", "Arbitrum", "Optimism", "zkSync", "Starknet", "Base"]
    Enum.random(partners)
  end

  def generate_ceo_name do
    first_names = ["Sarah", "Michael", "Jessica", "David", "Emily", "Alex", "Sophia", "James"]
    last_names = ["Chen", "Rodriguez", "Thompson", "Williams", "Martinez", "Anderson", "Lee", "Garcia"]
    "#{Enum.random(first_names)} #{Enum.random(last_names)}"
  end

  def generate_location do
    cities = ["New York", "San Francisco", "London", "Singapore", "Dubai", "Tokyo", "Berlin", "Miami"]
    Enum.random(cities)
  end

  def generate_intro(company, partner, category) do
    intros = [
      "#{company} has announced a groundbreaking partnership with #{partner} to revolutionize the #{category} space with cutting-edge blockchain technology.",
      "The #{category} industry is about to change forever. #{company}, in collaboration with #{partner}, just unveiled a game-changing solution.",
      "#{company} and #{partner} are joining forces to bring institutional-grade #{category} solutions to millions of users worldwide.",
      "Breaking news in #{category}: #{company} launches innovative platform powered by #{partner}'s infrastructure."
    ]
    Enum.random(intros)
  end

  def generate_body_paragraph_1(company, partner, category) do
    "Users across major markets can now access #{company}'s platform, which leverages #{partner}'s cutting-edge infrastructure. The integration brings unprecedented speed, security, and cost-effectiveness to #{category} operations, eliminating traditional friction points that have long plagued the industry."
  end

  def generate_body_paragraph_2(company) do
    "The platform introduces a seamless user experience that requires no technical knowledge. With #{company}'s intuitive interface, even complete beginners can navigate complex #{String.downcase(generate_category())} operations with confidence."
  end

  def generate_quote(company) do
    quotes = [
      "We've built something truly revolutionary. This changes everything for our users. No more complexity, no more barriers.",
      "Our mission has always been to make advanced technology accessible to everyone. Today, we're delivering on that promise.",
      "This partnership represents the future of the industry. We're not just improving existing solutions—we're reimagining what's possible.",
      "Users told us what they needed, and we listened. This is the result of thousands of hours of development and countless iterations."
    ]
    Enum.random(quotes)
  end

  def generate_bullet_1(category) do
    "Access cutting-edge #{category} solutions instantly"
  end

  def generate_bullet_2 do
    "Reduce costs by up to 90% compared to traditional methods"
  end

  def generate_bullet_3 do
    "Experience enterprise-grade security and compliance"
  end

  def generate_bullet_4 do
    "Benefit from 24/7 customer support and onboarding assistance"
  end

  def generate_bullet_5 do
    "Integrate seamlessly with existing workflows and systems"
  end

  def generate_conclusion(company, partner) do
    "This creates an unprecedented opportunity for mainstream adoption. #{company}'s platform, powered by #{partner}'s robust infrastructure, bridges the gap between traditional systems and next-generation technology."
  end

  def generate_why_matters(company, category) do
    "Today, many #{category} users still face significant barriers to entry. #{company}'s new platform removes these obstacles with a focus on user experience, security, and accessibility. The solution offers unparalleled performance while maintaining the highest standards of regulatory compliance."
  end

  def generate_final_quote do
    quotes = [
      "This is exactly what the industry needs right now. It's a perfect example of innovation meeting practical utility.",
      "The technology speaks for itself. This platform will set new standards for years to come.",
      "We're witnessing a pivotal moment in the evolution of digital infrastructure. This changes the competitive landscape.",
      "What makes this special isn't just the technology—it's how accessible they've made it for everyday users."
    ]
    Enum.random(quotes)
  end

  def generate_technical_details(company, partner, category) do
    "#{company}, which serves millions of users globally, partnered with #{partner} to bring enterprise-grade #{category} infrastructure to market. #{partner}'s technology enables seamless cross-chain operations with sub-second finality. #{company} delivers these capabilities through an intuitive interface available on web, iOS, and Android. Together, they're creating the next generation of #{category} solutions—one that prioritizes both power users and newcomers alike."
  end

  def generate_category do
    categories = ["DeFi", "NFT", "Gaming", "Trading", "Investment", "Blockchain"]
    Enum.random(categories)
  end
end

# Function to generate excerpt from content
defp generate_excerpt(title) do
  String.slice(title, 0..150) <> "..."
end

# Generate posts for each category
IO.puts("\nGenerating posts...")

for category <- categories do
  IO.puts("\nCategory: #{category.name}")

  # Generate 10 posts for this category
  for i <- 1..10 do
    # Generate unique title
    title = case i do
      1 -> "#{ContentGenerator.generate_company_name()} Partners with #{ContentGenerator.generate_partner_name()} for #{category.name} Innovation"
      2 -> "Breaking: #{category.name} Platform Reaches $1B Trading Volume in Record Time"
      3 -> "How #{ContentGenerator.generate_company_name()} is Revolutionizing #{category.name} with AI"
      4 -> "#{category.name} Giant Announces Major Partnership with Fortune 500 Company"
      5 -> "New #{category.name} Protocol Promises 100x Faster Transactions"
      6 -> "#{ContentGenerator.generate_company_name()} Raises $50M to Expand #{category.name} Operations"
      7 -> "Industry Leaders Unite to Transform #{category.name} Landscape"
      8 -> "#{category.name} Adoption Surges as #{ContentGenerator.generate_company_name()} Launches Mobile App"
      9 -> "Exclusive: #{category.name} Platform Integrates Advanced Security Features"
      10 -> "#{ContentGenerator.generate_company_name()} and #{ContentGenerator.generate_partner_name()} Unveil #{category.name} Solution"
    end

    # Generate slug
    slug = title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.slice(0..99)

    # Check if post already exists
    existing = Repo.get_by(Post, slug: slug)

    if existing do
      IO.puts("  Post #{i}: Skipping (already exists) - #{title}")
    else
      # Select random tags (6 tags)
      selected_tags = Enum.take_random(all_tags, 6)

      # Select random featured image
      featured_image = Enum.random(images)

      # Generate content
      content = ContentGenerator.generate_content(title, category.name, author.username || author.email)

      # Create post
      {:ok, post} = %Post{}
      |> Post.changeset(%{
        title: title,
        slug: slug,
        content: content,
        excerpt: generate_excerpt(title),
        author_id: author.id,
        category_id: category.id,
        featured_image: featured_image,
        published_at: DateTime.utc_now() |> DateTime.add(-Enum.random(1..30), :day),
        view_count: Enum.random(100..5000)
      })
      |> Repo.insert()

      # Associate tags
      Enum.each(selected_tags, fn tag ->
        Repo.insert_all("post_tags", [[post_id: post.id, tag_id: tag.id]])
      end)

      IO.puts("  Post #{i}: ✓ Created - #{title}")
    end
  end
end

IO.puts("\n✅ Post generation complete!")
IO.puts("Total posts created: #{Repo.aggregate(Post, :count, :id)}")
