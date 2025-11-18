defmodule BlocksterV2Web.WaitlistAdminLive do
  use BlocksterV2Web, :live_view
  alias BlocksterV2.Waitlist

  @impl true
  def mount(_params, _session, socket) do
    waitlist_emails = Waitlist.list_waitlist_emails()

    socket =
      socket
      |> assign(page_title: "Waitlist Admin")
      |> assign(waitlist_emails: waitlist_emails)
      |> assign(copied_email: nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("copy_email", %{"email" => email}, socket) do
    {:noreply, assign(socket, copied_email: email)}
  end

  @impl true
  def handle_event("download_csv", _params, socket) do
    csv_content = generate_csv(socket.assigns.waitlist_emails)

    {:noreply,
     socket
     |> push_event("download_csv", %{
       content: csv_content,
       filename: "waitlist_emails_#{Date.utc_today()}.csv"
     })}
  end

  defp generate_csv(waitlist_emails) do
    header = "Email,Signed Up,Verified\n"

    rows =
      Enum.map(waitlist_emails, fn email ->
        verified = if email.verified_at, do: "Yes", else: "No"

        signup_date =
          email.inserted_at
          |> Calendar.strftime("%Y-%m-%d %H:%M:%S")

        "#{email.email},#{signup_date},#{verified}"
      end)
      |> Enum.join("\n")

    header <> rows
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-8">
        <h1 class="text-3xl font-bold">Waitlist Emails</h1>
        <button
          phx-click="download_csv"
          class="bg-green-600 hover:bg-green-700 text-white font-bold py-2 px-6 rounded-lg transition-colors"
        >
          Download CSV
        </button>
      </div>

      <div class="bg-white rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Email
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Signed Up
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Status
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <tr :for={email <- @waitlist_emails} class="hover:bg-gray-50">
              <td class="px-6 py-4 whitespace-nowrap">
                <div class="text-sm font-medium text-gray-900"><%= email.email %></div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <div class="text-sm text-gray-500">
                  <%= Calendar.strftime(email.inserted_at, "%Y-%m-%d %H:%M") %>
                </div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span
                  :if={email.verified_at}
                  class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-green-100 text-green-800"
                >
                  Verified
                </span>
                <span
                  :if={!email.verified_at}
                  class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-yellow-100 text-yellow-800"
                >
                  Pending
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                <button
                  phx-click="copy_email"
                  phx-value-email={email.email}
                  data-email={email.email}
                  class="text-indigo-600 hover:text-indigo-900 copy-email-btn"
                >
                  <%= if @copied_email == email.email do %>
                    Copied!
                  <% else %>
                    Copy
                  <% end %>
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={length(@waitlist_emails) == 0} class="text-center py-12">
          <p class="text-gray-500 text-lg">No waitlist emails yet.</p>
        </div>
      </div>

      <div class="mt-6 text-gray-600">
        <p class="text-sm">
          Total emails: <span class="font-semibold"><%= length(@waitlist_emails) %></span>
        </p>
        <p class="text-sm">
          Verified: <span class="font-semibold"><%= Enum.count(@waitlist_emails, & &1.verified_at) %></span>
        </p>
        <p class="text-sm">
          Pending: <span class="font-semibold"><%= Enum.count(@waitlist_emails, &(!&1.verified_at)) %></span>
        </p>
      </div>
    </div>

    <script>
      // Copy to clipboard functionality
      window.addEventListener("phx:page-loading-stop", () => {
        document.querySelectorAll('.copy-email-btn').forEach(button => {
          button.addEventListener('click', (e) => {
            const email = e.target.dataset.email;
            if (email) {
              navigator.clipboard.writeText(email);
            }
          });
        });
      });

      // CSV download functionality
      window.addEventListener("phx:download_csv", (e) => {
        const { content, filename } = e.detail;
        const blob = new Blob([content], { type: 'text/csv' });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        window.URL.revokeObjectURL(url);
      });
    </script>
    """
  end
end
