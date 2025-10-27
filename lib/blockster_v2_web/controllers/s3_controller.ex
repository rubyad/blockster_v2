defmodule BlocksterV2Web.S3Controller do
  use BlocksterV2Web, :controller

  alias BlocksterV2.S3Upload

  def presigned_url(conn, %{"filename" => filename, "content_type" => content_type}) do
    case S3Upload.generate_presigned_url(filename, content_type) do
      {:ok, %{upload_url: upload_url, public_url: public_url}} ->
        json(conn, %{
          upload_url: upload_url,
          public_url: public_url
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: reason})
    end
  end

  def presigned_url(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameters: filename and content_type"})
  end
end
