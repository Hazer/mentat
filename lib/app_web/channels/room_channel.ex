defmodule AppWeb.RoomChannel do
  use Phoenix.Channel
  import Ecto.Query
  require Logger
  alias App.{Repo, Message, Tag, Team, MessageTag, User}
  alias AppWeb.{MessageView, TagView, Presence}
  alias Scrape.Website

  def join("room:" <> private_room_id, %{"tags" => tags, "uuid" => uuid, "color" => color}, socket) do
    team = Repo.one(from t in Team, where: t.name == ^private_room_id)
    tag_ids = Repo.all(from t in Tag, where: t.name in ^tags and t.team_id == ^team.id, select: t.id)
    user = Repo.one(from u in User, where: u.uuid == ^uuid) || Repo.insert!(%User{uuid: uuid, color: color})

    messages = case length(tag_ids) do
      0 -> Repo.all(from m in Message, where: m.team_id == ^team.id, order_by: [desc: m.inserted_at], limit: 15)
      _ -> Repo.all(from m in Message, join: t in MessageTag, on:  m.id == t.message_id, where: m.team_id == ^team.id and t.tag_id in ^tag_ids, order_by: [desc: m.inserted_at], limit: 15, distinct: true )
    end

    messages = Repo.preload messages, [:tags, :user]
    rendered_messages = MessageView.render("index.json", %{messages: messages})
    tags = Repo.all(from t in Tag, where: t.team_id == ^team.id)
    rendered_tags = TagView.render("index.json", %{tags: tags})
    send(self(), :after_join)
    {:ok, %{messages: rendered_messages, tags: rendered_tags, name: user.name, color: user.color}, assign(socket, :team_id, team.id)}
  end

  def handle_in("more_messages", %{"id" => id, "tags" => tags}, socket) do
    team_id = socket.assigns.team_id
    tag_ids = Repo.all(from t in Tag, where: t.name in ^tags and t.team_id == ^team_id, select: t.id)
    messages = case length(tag_ids) do
      0 -> Repo.all(from m in Message, where: m.team_id == ^team_id and m.id < ^id, order_by: [desc: m.inserted_at], limit: 15)
      _ -> Repo.all(from m in Message, join: t in MessageTag, on:  m.id == t.message_id, where: m.team_id == ^team_id and t.tag_id in ^tag_ids and m.id < ^id, order_by: [desc: m.inserted_at], limit: 15, distinct: true )
    end
    messages = Repo.preload messages, [:tags, :user]
    rendered_messages = MessageView.render("index.json", %{messages: messages})
    {:reply, {:ok, %{messages: rendered_messages}}, socket}
  end

  def handle_in("new_msg", %{"uuid" => uuid, "room" => team, "tags" => tags, "text" => text, "urls" => urls}, socket) do
    # TODO run a set of validations on message here:
    #### 3. Each tag has string length > 0

    user = Repo.one(from u in User, where: u.uuid == ^uuid)
    team_id = socket.assigns.team_id
    tag_ids = Repo.all(from t in Tag, where: t.name in ^tags and t.team_id == ^team_id)
    Enum.each(tags, fn(t) -> if !Enum.any?(tag_ids, fn(i) -> i.name == t end), do: Repo.insert!(%Tag{team_id: team_id, name: t}) end)
    message = Repo.insert!(%Message{body: text, team_id: team_id, user_id: user.id})
    broadcast! socket, "new_msg", %{text: text, name: user.name, color: user.color, tags: tags, room: team, id: message.id, uuid: uuid}
    final_tags = Repo.all(from t in Tag, where: t.name in ^tags and t.team_id == ^team_id)
    Enum.each(final_tags, fn(t) -> Repo.insert!(%MessageTag{message_id: message.id, tag_id: t.id}) end)
    rendered_url = cond do
      urls |> Enum.any? ->
        url = Enum.at(urls, 0)
        case HTTPoison.get(url, [], [follow_redirect: true]) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body, headers: headers, request_url: request_url}} ->
            {_, type} = List.keyfind(headers, "content-type", 0) || List.keyfind(headers, "Content-Type", 0)
            cond do
              type |> String.starts_with?("image") ->
                %{content_type: type, url: request_url, show: true}
              type |> String.starts_with?("text/html") ->
                parse = Website.parse(body, request_url)
                %{content_type: type, url: request_url, title: parse.title, description: parse.description, image: parse.image, show: true}
              true ->
                %{show: false}
            end
          {:ok, %HTTPoison.Response{status_code: 404}} ->
            %{show: false}
          {:error, %HTTPoison.Error{reason: reason}} ->
            %{show: false}
        end
      true ->
        %{show: false}
    end
    message = Ecto.Changeset.change(message, %{url_data: rendered_url})
    message = Repo.update!(message)
    if rendered_url.show do
      broadcast! socket, "new_url_data", %{id: message.id, url_data: rendered_url}
    end
    {:reply, {:ok, %{}}, socket}
  end

  def handle_in("new_tags", %{"tags" => tags}, socket) do
    team_id = socket.assigns.team_id
    current_tags = Repo.all(from t in Tag, where: t.name in ^tags and t.team_id == ^team_id)
    Enum.each(tags, fn(t) -> if !Enum.any?(current_tags, fn(i) -> i.name == t end), do: Repo.insert!(%Tag{team_id: team_id, name: t}) end)
    tag_ids = Repo.all(from t in Tag, where: t.name in ^tags and t.team_id == ^team_id, select: t.id)
    messages = case length(tag_ids) do
      0 -> Repo.all(from m in Message, where: m.team_id == ^team_id, order_by: [desc: m.inserted_at], limit: 15)
      _ -> Repo.all(from m in Message, join: t in MessageTag, on:  m.id == t.message_id, where: m.team_id == ^team_id and t.tag_id in ^tag_ids, order_by: [desc: m.inserted_at], limit: 15, distinct: true )
    end
    messages = Repo.preload messages, [:tags, :user]
    rendered_todos = MessageView.render("index.json", %{messages: messages})
    {:reply, {:ok, %{messages: rendered_todos}}, socket}
  end

  def handle_in("new_message_tag", %{"id" => id, "newTag" => new_tag}, socket) do
    team_id = socket.assigns.team_id
    tag = Repo.one(from t in Tag, where: t.team_id == ^team_id and t.name == ^new_tag)
    if !tag do
      tag = Repo.insert!(%Tag{team_id: team_id, name: new_tag})
      Repo.insert!(%MessageTag{message_id: id, tag_id: tag.id})
      broadcast! socket, "new_message_tag", %{id: id, new_tag: new_tag}
    else
      message_tag = Repo.one(from t in MessageTag, where: t.tag_id == ^tag.id and t.message_id == ^id)
      if !message_tag do
        Repo.insert!(%MessageTag{message_id: id, tag_id: tag.id})
        broadcast! socket, "new_message_tag", %{id: id, new_tag: new_tag}
      end
    end
    {:reply, {:ok, %{}}, socket}
  end

  def handle_in("new_name", %{"uuid" => uuid, "name" => name, "color" => color}, socket) do
    user = Repo.one(from u in User, where: u.uuid == ^uuid)
    user = Ecto.Changeset.change(user, %{name: name, color: color})
    Repo.update!(user)
    broadcast! socket, "new_name", %{ name: name, uuid: uuid, color: color }
    {:noreply, socket}
  end

  def handle_in("new_typing", %{"uuid" => uuid, "typing" => typing}, socket) do
    broadcast! socket, "new_typing", %{uuid: uuid, typing: typing}
    {:noreply, socket}
  end

  def handle_in("approve_request", %{"encryptedGroupPrivateKey" => encrypted_group_private_key, "uuid" => uuid, "groupPublicKey" => group_public_key}, socket) do
    broadcast! socket, "approve_request", %{uuid: uuid, encrypted_group_private_key: encrypted_group_private_key, group_public_key: group_public_key}
    {:noreply, socket}
  end

  def handle_in("new_claim_or_invite", %{"uuid" => uuid, "name" => name, "publicKey" => public_key}, socket) do
    team_id = socket.assigns.team_id
    team = Repo.one(from t in Team, where: t.id == ^team_id)
    if (!team.claim_uuid) do
      team = Ecto.Changeset.change(team, %{claim_uuid: uuid})
      Repo.update!(team)
      broadcast! socket, "new_claim_or_invite", %{uuid: uuid, claimed: true}
    else
      if team.claim_uuid == uuid do
        broadcast! socket, "new_claim_or_invite", %{uuid: uuid, claimed: true}
      else
        broadcast! socket, "new_claim_or_invite", %{uuid: uuid, claimed: false, name: name, public_key: public_key}
      end
    end
    {:noreply, socket}
  end

  def handle_info(:after_join, socket) do
    push socket, "presence_state", Presence.list(socket)
    uuid = socket.assigns.uuid
    user = Repo.one(from u in User, where: u.uuid == ^uuid)

    {:ok, _} = Presence.track(socket, socket.assigns.uuid, %{
      online_at: inspect(System.system_time(:seconds)),
      name: user.name,
      color: user.color
    })
    {:noreply, socket}
  end
end