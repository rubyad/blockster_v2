alias BlocksterV2.Repo
alias BlocksterV2.Events.Event
alias BlocksterV2.Blog.Tag

# Get all events and tags
events = Repo.all(Event)
tags = Repo.all(Tag)

IO.puts("Found #{length(events)} events and #{length(tags)} tags")

# Add 5 random tags to each event
Enum.each(events, fn event ->
  # Get 5 random tags
  random_tags = Enum.take_random(tags, 5)

  # Preload existing tags to avoid duplicates
  event = Repo.preload(event, :tags)

  # Associate the random tags with the event
  event
  |> Ecto.Changeset.change()
  |> Ecto.Changeset.put_assoc(:tags, random_tags)
  |> Repo.update!()

  tag_names = Enum.map(random_tags, & &1.name)
  IO.puts("Added tags to '#{event.title}': #{Enum.join(tag_names, ", ")}")
end)

IO.puts("\nSuccessfully added 5 random tags to each event!")
