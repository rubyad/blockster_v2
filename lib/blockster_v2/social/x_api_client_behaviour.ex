defmodule BlocksterV2.Social.XApiClientBehaviour do
  @moduledoc "Behaviour for XApiClient, enabling Mox mocking in tests."

  @callback create_tweet(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback get_user_by_username(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback get_user_tweets_with_metrics(String.t(), String.t(), integer()) :: {:ok, list()} | {:error, term()}
  @callback get_user_with_metrics(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
end
