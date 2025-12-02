defmodule BlocksterV2Web.ShopLive.Index do
  use BlocksterV2Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    products = get_sample_products()

    {:ok,
     socket
     |> assign(:page_title, "Shop - Browse Products")
     |> assign(:products, products)
     |> assign(:show_community_dropdown, false)
     |> assign(:show_artist_dropdown, false)
     |> assign(:show_basics_dropdown, false)
     |> assign(:community_search, "")
     |> assign(:artist_search, "")
     |> assign(:basics_search, "")
     |> assign(:selected_community, nil)
     |> assign(:selected_artist, nil)
     |> assign(:selected_basics, nil)}
  end

  @impl true
  def handle_event("toggle_dropdown", %{"filter" => filter}, socket) do
    case filter do
      "community" ->
        {:noreply,
         assign(socket,
           show_community_dropdown: !socket.assigns.show_community_dropdown,
           show_artist_dropdown: false,
           show_basics_dropdown: false
         )}

      "artist" ->
        {:noreply,
         assign(socket,
           show_artist_dropdown: !socket.assigns.show_artist_dropdown,
           show_community_dropdown: false,
           show_basics_dropdown: false
         )}

      "basics" ->
        {:noreply,
         assign(socket,
           show_basics_dropdown: !socket.assigns.show_basics_dropdown,
           show_community_dropdown: false,
           show_artist_dropdown: false
         )}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_search", %{"filter" => filter, "value" => value}, socket) do
    case filter do
      "community" ->
        {:noreply, assign(socket, :community_search, value)}

      "artist" ->
        {:noreply, assign(socket, :artist_search, value)}

      "basics" ->
        {:noreply, assign(socket, :basics_search, value)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_option", %{"filter" => filter, "option" => option}, socket) do
    case filter do
      "community" ->
        {:noreply,
         assign(socket,
           selected_community: option,
           selected_artist: nil,
           selected_basics: nil,
           show_community_dropdown: false
         )}

      "artist" ->
        {:noreply,
         assign(socket,
           selected_artist: option,
           selected_community: nil,
           selected_basics: nil,
           show_artist_dropdown: false
         )}

      "basics" ->
        {:noreply,
         assign(socket,
           selected_basics: option,
           selected_community: nil,
           selected_artist: nil,
           show_basics_dropdown: false
         )}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_filter", %{"filter" => filter}, socket) do
    case filter do
      "community" ->
        {:noreply, assign(socket, :selected_community, nil)}

      "artist" ->
        {:noreply, assign(socket, :selected_artist, nil)}

      "basics" ->
        {:noreply, assign(socket, :selected_basics, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  defp get_sample_products do
    [
      %{
        id: 1,
        name: "Cargo Comfort Pants",
        slug: "cargo-comfort-pants",
        price: 50.00,
        original_price: 65.00,
        image: "https://ik.imagekit.io/blockster/coming-soon-card-image1.png?tr=w-500",
        bux_discount: 1264,
        discount_percent: 25
      },
      %{
        id: 2,
        name: "Unofficial Cargo Pants",
        slug: "unofficial-cargo-pants",
        price: 50.00,
        original_price: 65.00,
        image: "https://ik.imagekit.io/blockster/coming-soon-card-image2.png?tr=w-500",
        bux_discount: 1264,
        discount_percent: 25
      },
      %{
        id: 3,
        name: "Blockster Sneakers",
        slug: "blockster-sneakers",
        price: 50.00,
        original_price: 65.00,
        image: "https://ik.imagekit.io/blockster/coming-soon-shoe.png?tr=w-500",
        bux_discount: 1264,
        discount_percent: 25
      },
      %{
        id: 4,
        name: "Unofficial Standard Hoodie",
        slug: "unofficial-standard-hoodie",
        price: 50.00,
        original_price: 65.00,
        image: "https://ik.imagekit.io/blockster/hoode-comnmg-soon.png",
        bux_discount: 1264,
        discount_percent: 25
      },
      %{
        id: 5,
        name: "Crypto Street Jacket",
        slug: "crypto-street-jacket",
        price: 75.00,
        original_price: 95.00,
        image: "https://ik.imagekit.io/blockster/coming-soon-card-image1.png?tr=w-500",
        bux_discount: 1580,
        discount_percent: 21
      },
      %{
        id: 6,
        name: "Blockster Classic Tee",
        slug: "blockster-classic-tee",
        price: 35.00,
        original_price: 45.00,
        image: "https://ik.imagekit.io/blockster/coming-soon-card-image2.png?tr=w-500",
        bux_discount: 884,
        discount_percent: 22
      },
      %{
        id: 7,
        name: "Web3 Cap",
        slug: "web3-cap",
        price: 25.00,
        original_price: 35.00,
        image: "https://ik.imagekit.io/blockster/coming-soon-shoe.png?tr=w-500",
        bux_discount: 632,
        discount_percent: 29
      },
      %{
        id: 8,
        name: "NFT Collector Backpack",
        slug: "nft-collector-backpack",
        price: 85.00,
        original_price: 110.00,
        image: "https://ik.imagekit.io/blockster/hoode-comnmg-soon.png",
        bux_discount: 2106,
        discount_percent: 23
      },
      %{
        id: 9,
        name: "Decentralized Joggers",
        slug: "decentralized-joggers",
        price: 60.00,
        original_price: 80.00,
        image: "https://ik.imagekit.io/blockster/coming-soon-card-image1.png?tr=w-500",
        bux_discount: 1516,
        discount_percent: 25
      },
      %{
        id: 10,
        name: "Blockchain Bomber",
        slug: "blockchain-bomber",
        price: 90.00,
        original_price: 120.00,
        image: "https://ik.imagekit.io/blockster/coming-soon-card-image2.png?tr=w-500",
        bux_discount: 2274,
        discount_percent: 25
      },
      %{
        id: 11,
        name: "Smart Contract Socks",
        slug: "smart-contract-socks",
        price: 15.00,
        original_price: 20.00,
        image: "https://ik.imagekit.io/blockster/coming-soon-shoe.png?tr=w-500",
        bux_discount: 380,
        discount_percent: 25
      },
      %{
        id: 12,
        name: "DeFi Denim Jacket",
        slug: "defi-denim-jacket",
        price: 95.00,
        original_price: 125.00,
        image: "https://ik.imagekit.io/blockster/hoode-comnmg-soon.png",
        bux_discount: 2400,
        discount_percent: 24
      }
    ]
  end
end
