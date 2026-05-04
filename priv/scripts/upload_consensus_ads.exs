uploads = [
  {
    "/Users/tenmerry/Projects/blockster_v2/priv/static/images/ads/consensus-square.png",
    "ads/consensus/consensus-2026-square.png"
  },
  {
    "/Users/tenmerry/Projects/blockster_v2/priv/static/images/ads/consensus-portrait.png",
    "ads/consensus/consensus-2026-portrait.png"
  }
]

bucket = Application.get_env(:blockster_v2, :s3_bucket)
region = Application.get_env(:blockster_v2, :s3_region, "us-east-1")

config = %{
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: region
}

if is_nil(config.access_key_id) or is_nil(config.secret_access_key) do
  IO.puts("✗ AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY not set in env")
  System.halt(1)
end

for {source, s3_key} <- uploads do
  binary = File.read!(source)
  size_kb = Float.round(byte_size(binary) / 1024, 1)

  IO.puts("Uploading #{Path.basename(source)} (#{size_kb} KB) → s3://#{bucket}/#{s3_key}")

  result =
    ExAws.S3.put_object(bucket, s3_key, binary,
      content_type: "image/png",
      cache_control: "public, max-age=31536000, immutable"
    )
    |> ExAws.request(config)

  case result do
    {:ok, _} ->
      IO.puts("  ✓ https://ik.imagekit.io/blockster/#{s3_key}")

    {:error, reason} ->
      IO.puts("  ✗ #{inspect(reason)}")
      System.halt(1)
  end
end
