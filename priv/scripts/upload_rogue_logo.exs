source_path =
  "/Users/tenmerry/Projects/roguetrader/priv/static/images/logo/rogue-trader-160.png"

s3_key = "rogue-trader-logo.png"

bucket = Application.get_env(:blockster_v2, :s3_bucket)
region = Application.get_env(:blockster_v2, :s3_region, "us-east-1")

binary = File.read!(source_path)
size_kb = Float.round(byte_size(binary) / 1024, 1)

IO.puts("Uploading #{Path.basename(source_path)} (#{size_kb} KB) → s3://#{bucket}/#{s3_key}")

config = %{
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: region
}

result =
  ExAws.S3.put_object(bucket, s3_key, binary,
    content_type: "image/png",
    cache_control: "public, max-age=31536000, immutable"
  )
  |> ExAws.request(config)

case result do
  {:ok, _} ->
    public_url = "https://#{bucket}.s3.#{region}.amazonaws.com/#{s3_key}"
    imagekit_url = "https://ik.imagekit.io/blockster/#{s3_key}"
    IO.puts("✓ Uploaded")
    IO.puts("  S3: #{public_url}")
    IO.puts("  ImageKit: #{imagekit_url}")

  {:error, reason} ->
    IO.puts("✗ Upload failed: #{inspect(reason)}")
    System.halt(1)
end
