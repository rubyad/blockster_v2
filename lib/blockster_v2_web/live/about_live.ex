defmodule BlocksterV2Web.AboutLive do
  use BlocksterV2Web, :live_view

  @founders [
    %{
      name: "Lidia Yadlos",
      title: "Co-founder & Editor-in-Chief",
      bio:
        "Lidia built out the newsrooms at two crypto publications before Blockster, managing a staff of 30+ writers covering everything from the merge to the FTX collapse. She treats a story lead like a ticker symbol — watch for the volume spike. Based in Lisbon.",
      image:
        "https://images.unsplash.com/photo-1580489944761-15a19d654956?w=800&q=85&auto=format&fit=crop&crop=faces",
      socials: [
        %{label: "X", href: "https://x.com/"},
        %{label: "LinkedIn", href: "https://linkedin.com/"}
      ]
    },
    %{
      name: "Erik Spivak",
      title: "Co-founder & CTO",
      bio:
        "Erik wrote payment infrastructure at a fintech unicorn before going down the Solana rabbit hole in 2022. He's an Elixir core contributor in spirit and a reluctant Rust evangelist. If it settles on-chain, Erik shipped it. Based in Tel Aviv.",
      image:
        "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800&q=85&auto=format&fit=crop&crop=faces",
      socials: [
        %{label: "X", href: "https://x.com/"},
        %{label: "GitHub", href: "https://github.com/"}
      ]
    },
    %{
      name: "Adam Todd",
      title: "Co-founder & CEO",
      bio:
        "Adam spent a decade building distributed systems and another trying to make tokenomics actually work. Blockster is his third swing at a media product — this one with the economics built in from day one. Based in Miami.",
      image:
        "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=800&q=85&auto=format&fit=crop&crop=faces",
      socials: [
        %{label: "X", href: "https://x.com/"},
        %{label: "LinkedIn", href: "https://linkedin.com/"}
      ]
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "About Blockster")
     |> assign(:founders, @founders)}
  end
end
