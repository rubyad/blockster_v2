defmodule BlocksterV2.ImageKit do
  @moduledoc """
  Helper module for generating ImageKit URLs from S3 URLs.
  ImageKit is configured to use the S3 bucket as origin.
  """

  @imagekit_base "https://ik.imagekit.io/blockster"

  @doc """
  Converts an S3 URL to an ImageKit URL with optional transformations.

  ## Parameters
    - url: The original image URL (S3 or any URL)
    - opts: Keyword list of transformation options
      - :width - Target width in pixels
      - :height - Target height in pixels
      - :quality - Image quality (1-100)
      - :format - Output format (auto, webp, jpg, png)

  ## Examples

      iex> ImageKit.url("https://bucket.s3.region.amazonaws.com/image.jpg", width: 400, height: 300)
      "https://ik.imagekit.io/blockster/image.jpg?tr=w-400,h-300"

      iex> ImageKit.url(nil, width: 400)
      nil

  """
  def url(original_url, opts \\ [])
  def url(nil, _opts), do: nil
  def url("", _opts), do: nil

  def url(original_url, opts) do
    filename = extract_filename(original_url)

    if filename do
      transforms = build_transforms(opts)

      if transforms != "" do
        "#{@imagekit_base}/#{filename}?tr=#{transforms}"
      else
        "#{@imagekit_base}/#{filename}"
      end
    else
      # Return original URL if we can't parse it (e.g., external URLs)
      original_url
    end
  end

  # Specific size functions with dimensions in the name

  @doc "Square 400x400 - small card thumbnails"
  def w400_h400(url), do: url(url, width: 400, height: 400)

  @doc "Portrait 600x800 - tall/medium cards"
  def w600_h800(url), do: url(url, width: 600, height: 800)

  @doc "Landscape 800x600 - wide cards"
  def w800_h600(url), do: url(url, width: 800, height: 600)

  @doc "Portrait 230x320 - sidebar thumbnails"
  def w230_h320(url), do: url(url, width: 230, height: 320)

  @doc "Square 300x300 - small thumbnails"
  def w300_h300(url), do: url(url, width: 300, height: 300)

  @doc "Square 200x200 - icons/avatars"
  def w200_h200(url), do: url(url, width: 200, height: 200)

  @doc "Landscape 1200x800 - full width backgrounds"
  def w1200_h800(url), do: url(url, width: 1200, height: 800)

  @doc "Landscape 800x400 - hero banners"
  def w800_h400(url), do: url(url, width: 800, height: 400)

  @doc "Square 500x500 - medium thumbnails"
  def w500_h500(url), do: url(url, width: 500, height: 500)

  @doc "Portrait 400x600 - portrait cards"
  def w400_h600(url), do: url(url, width: 400, height: 600)

  @doc "Portrait 500x600 - tall cards"
  def w500_h600(url), do: url(url, width: 500, height: 600)

  @doc "Large 1200x1600 - post featured image (half screen)"
  def w1200_h1600(url), do: url(url, width: 1200, height: 1600)

  @doc "Mobile 640x800 - post featured image on mobile"
  def w640_h800(url), do: url(url, width: 640, height: 800)

  @doc "Content width 800 - post body images"
  def w800(url), do: url(url, width: 800)

  @doc "Content width 480 - post body images on mobile"
  def w480(url), do: url(url, width: 480)

  @doc "Landscape 640x360 - 16:9 card thumbnails"
  def w640_h360(url), do: url(url, width: 640, height: 360)

  # Extract the filename from an S3 URL
  # S3 URLs look like: https://bucket.s3.region.amazonaws.com/uploads/timestamp-random.ext
  # We want just the filename: timestamp-random.ext
  defp extract_filename(url) when is_binary(url) do
    cond do
      # Already an ImageKit URL - extract filename
      String.contains?(url, "ik.imagekit.io/blockster") ->
        url
        |> String.replace(~r{https?://ik\.imagekit\.io/blockster/?}, "")
        |> String.split("?")
        |> List.first()

      # S3 URL pattern: https://bucket.s3.region.amazonaws.com/path/filename.ext
      String.contains?(url, ".s3.") and String.contains?(url, ".amazonaws.com") ->
        # Get the full path after .amazonaws.com/
        case Regex.run(~r{\.amazonaws\.com/(.+)$}, url) do
          [_, path] -> path
          _ -> nil
        end

      # Local images starting with /images/
      String.starts_with?(url, "/images/") ->
        String.trim_leading(url, "/")

      true ->
        nil
    end
  end

  defp extract_filename(_), do: nil

  # Build the transformation string
  defp build_transforms(opts) do
    transforms =
      []
      |> maybe_add_transform(opts[:width], "w")
      |> maybe_add_transform(opts[:height], "h")
      |> maybe_add_transform(opts[:quality], "q")
      |> maybe_add_transform(opts[:format], "f")

    Enum.join(transforms, ",")
  end

  defp maybe_add_transform(transforms, nil, _key), do: transforms
  defp maybe_add_transform(transforms, value, key), do: transforms ++ ["#{key}-#{value}"]
end
