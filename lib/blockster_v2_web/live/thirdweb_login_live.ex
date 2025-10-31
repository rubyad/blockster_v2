defmodule BlocksterV2Web.ThirdwebLoginLive do
  use BlocksterV2Web, :live_component

  @impl true
  def render(assigns) do
    # Determine if this is mobile based on the id
    is_mobile = String.contains?(assigns[:id] || "", "mobile")

    button_classes = if is_mobile do
      "flex items-center gap-1.5 bg-gradient-to-r from-[#8AE388] to-[#BAF55F] rounded-[100px] px-3 py-2 cursor-pointer"
    else
      "flex items-center gap-1.5 bg-gradient-to-r from-[#8AE388] to-[#BAF55F] rounded-[100px] px-6 py-3 hover:shadow-lg transition-all cursor-pointer"
    end

    text_classes = if is_mobile do
      "text-xs font-haas_medium_65 text-[#141414]"
    else
      "text-md font-haas_medium_65 text-[#141414]"
    end

    assigns = assign(assigns, button_classes: button_classes, text_classes: text_classes)

    ~H"""
    <div id={"thirdweb-login-#{@id}"} phx-hook="ThirdwebLogin" class="thirdweb-login-container">
      <button class={@button_classes}>
        <span class={@text_classes}>Connect wallet</span>
      </button>
    </div>
    """
  end
end
