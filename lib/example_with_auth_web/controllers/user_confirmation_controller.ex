defmodule ExampleWithAuthWeb.UserConfirmationController do
  use ExampleWithAuthWeb, :controller

  alias ExampleWithAuth.Accounts
  require Ash.Query

  def new(conn, _params) do
    render(conn, "new.html")
  end

  def create(conn, %{"user" => %{"email" => email}}) do
    user =
      ExampleWithAuth.Accounts.User
      |> Ash.Query.filter(email == ^email)
      |> ExampleWithAuth.Accounts.Api.read_one!()

    if user do
      user
      |> Ash.Changeset.new()
      |> Ash.Changeset.for_update(:deliver_user_confirmation_instructions, %{
        confirmation_url_fun: &Routes.user_confirmation_url(conn, :confirm, &1)
      })
      |> Accounts.Api.update!()
    end

    # Regardless of the outcome, show an impartial success/error message.
    conn
    |> put_flash(
      :info,
      "If your email is in our system and it has not been confirmed yet, " <>
        "you will receive an email with instructions shortly."
    )
    |> redirect(to: "/")
  end

  # Do not log in the user after confirmation to avoid a
  # leaked token giving the user access to the account.
  def confirm(conn, %{"token" => token}) do
    result =
      ExampleWithAuth.Accounts.User
      |> Ash.Query.for_read(:with_verified_email_token, token: token, context: "confirm")
      |> ExampleWithAuth.Accounts.Api.read_one()
      |> case do
        {:ok, user} when not is_nil(user) ->
          user
          |> Ash.Changeset.new()
          |> Ash.Changeset.for_update(:confirm, %{delete_confirm_tokens: true, token: token})
          |> ExampleWithAuth.Accounts.Api.update()
          |> case do
            {:ok, user} ->
              {:ok, user}

            _ ->
              :error
          end

        _ ->
          :error
      end

    case result do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Account confirmed successfully.")
        |> redirect(to: "/")

      :error ->
        # If there is a current user and the account was already confirmed,
        # then odds are that the confirmation link was already visited, either
        # by some automation or by the user themselves, so we redirect without
        # a warning message.
        case conn.assigns do
          %{current_user: %{confirmed_at: confirmed_at}} when not is_nil(confirmed_at) ->
            redirect(conn, to: "/")

          %{} ->
            conn
            |> put_flash(:error, "Account confirmation link is invalid or it has expired.")
            |> redirect(to: "/")
        end
    end
  end
end
