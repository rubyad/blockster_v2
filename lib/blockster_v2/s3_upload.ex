defmodule BlocksterV2.S3Upload do
  @moduledoc """
  Handles S3 file uploads and presigned URL generation.
  """

  @doc """
  Generates a presigned URL for uploading a file to S3.

  ## Examples

      iex> S3Upload.generate_presigned_url("image.jpg", "image/jpeg")
      {:ok, %{upload_url: "https://...", public_url: "https://..."}}

  """
  def generate_presigned_url(filename, content_type) do
    bucket = Application.get_env(:blockster_v2, :s3_bucket)
    region = Application.get_env(:blockster_v2, :s3_region, "us-east-1")

    # Generate unique filename with timestamp
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    ext = Path.extname(filename)

    unique_filename =
      "uploads/#{timestamp}-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}#{ext}"

    # Configure S3
    config = %{
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
      region: region
    }

    # Generate presigned URL for PUT operation
    {:ok, presigned_url} =
      ExAws.Config.new(:s3, config)
      |> ExAws.S3.presigned_url(:put, bucket, unique_filename,
        expires_in: 3600,
        query_params: [{"Content-Type", content_type}]
      )

    # Construct public URL
    public_url = "https://#{bucket}.s3.#{region}.amazonaws.com/#{unique_filename}"

    {:ok,
     %{
       upload_url: presigned_url,
       public_url: public_url,
       filename: unique_filename
     }}
  rescue
    error ->
      {:error, "Failed to generate presigned URL: #{inspect(error)}"}
  end

  @doc """
  Deletes a file from S3.

  ## Examples

      iex> S3Upload.delete("uploads/image.jpg")
      :ok

  """
  def delete(key) do
    bucket = Application.get_env(:blockster_v2, :s3_bucket)

    ExAws.S3.delete_object(bucket, key)
    |> ExAws.request()
    |> case do
      {:ok, _} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
