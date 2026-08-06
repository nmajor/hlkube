# Postiz OAuth setup

Postiz runs at `https://postiz.nmajor.net`.

## X (Twitter)

The Postiz X provider uses OAuth 1.0a consumer credentials:

- `X_API_KEY`
- `X_API_SECRET`

Configure the X app with:

- App permissions: `Read and Write`
- App type: `Native App`
- Callback URI: `https://postiz.nmajor.net/integrations/social/x`

The X bearer token is not used by Postiz for this integration.

## Meta: Facebook and Facebook-linked Instagram

The Postiz Facebook and Facebook-linked Instagram providers use the same Meta app credentials:

- `FACEBOOK_APP_ID`
- `FACEBOOK_APP_SECRET`

Configure these OAuth redirect URLs in the Meta app:

- `https://postiz.nmajor.net/integrations/social/facebook`
- `https://postiz.nmajor.net/integrations/social/instagram`

Use `https://postiz.nmajor.net/privacy` as the privacy policy URL.

Facebook pages require these permissions:

- `pages_show_list`
- `business_management`
- `pages_manage_posts`
- `pages_manage_engagement`
- `pages_read_engagement`
- `read_insights`

Instagram accounts require these permissions:

- `instagram_basic`
- `pages_show_list`
- `pages_read_engagement`
- `business_management`
- `instagram_content_publish`
- `instagram_manage_comments`
- `instagram_manage_insights`

The Instagram account must be a professional business account connected to a Facebook page the authenticating Facebook user can manage.

## Instagram standalone

The standalone provider connects directly to a professional Instagram account and does not require a linked Facebook page. It uses Instagram-specific credentials:

- `INSTAGRAM_APP_ID`
- `INSTAGRAM_APP_SECRET`

In Meta for Developers:

1. Create or select a Business app and add the Instagram product.
2. Set up **Instagram API with Instagram Login** / **Instagram Business Login**.
3. Add this exact OAuth redirect URI:

   `https://postiz.nmajor.net/integrations/social/instagram-standalone`

4. Copy the **Instagram App ID** and **Instagram App Secret** from the Instagram API setup screen. These are distinct from the Facebook app credentials.
5. For development-mode testing, add the target Instagram professional account as an Instagram Tester under App Roles, then accept the invitation in Instagram under **Apps and Websites**.
6. Put the credentials in `postiz-secrets.secret`, seal them, and deploy through Git/Flux.
7. In Postiz, choose **Add Channel** and then **Instagram (Standalone)**.

The account must be an Instagram professional account (Business or Creator). App roles can publish while the Meta app is in development mode; connecting accounts that do not have a role requires the relevant permissions and Meta App Review.

## Threads

The Postiz Threads provider uses credentials from a Meta app created with the **Access the Threads API** use case:

- `THREADS_APP_ID`
- `THREADS_APP_SECRET`

In Meta for Developers:

1. Create a new app and select **Access the Threads API**.
2. Configure API access with `threads_basic` and `threads_content_publish`.
3. In the Threads API settings, add this exact OAuth redirect URI:

   `https://postiz.nmajor.net/integrations/social/threads`

4. Meta requires values for the Uninstall Callback URL and Delete Callback URL before the form can be saved. The OAuth redirect URL above can be used for both, although Postiz does not currently implement those callbacks.
5. Copy the **Threads App ID** and the complete **Threads App Secret** from the Threads API **Settings** tab into `postiz-secrets.secret`.
6. Finish the Meta customization wizard by selecting **Finish customization** and confirming **Yes, I'm finished**.
7. For development-mode testing, add the target account under **App roles** as a **Threads Tester**. Accept the invitation at threads.com under **Settings > Website permissions > Invites**.
8. Seal and deploy the secret through Git/Flux, then select **Threads** from Postiz's **Add Channel** dialog.

The Threads App Secret is normally 32 characters. Make sure the full value is copied from Meta's narrow secret field.

## Google: YouTube

The YouTube provider uses:

- `YOUTUBE_CLIENT_ID`
- `YOUTUBE_CLIENT_SECRET`

Create a Google OAuth client with application type `Web application` and add this authorized redirect URI:

- `https://postiz.nmajor.net/integrations/social/youtube`

Enable these APIs for the Google Cloud project:

- YouTube Data API v3
- YouTube Analytics API

Postiz requests these scopes:

- `https://www.googleapis.com/auth/userinfo.profile`
- `https://www.googleapis.com/auth/userinfo.email`
- `https://www.googleapis.com/auth/youtube`
- `https://www.googleapis.com/auth/youtube.force-ssl`
- `https://www.googleapis.com/auth/youtube.readonly`
- `https://www.googleapis.com/auth/youtube.upload`
- `https://www.googleapis.com/auth/youtubepartner`
- `https://www.googleapis.com/auth/yt-analytics.readonly`

## Secret update workflow

1. Edit `apps/third-party/postiz/postiz-secrets.secret`.
2. Replace the provider's placeholders with the credentials from its developer portal.
3. Run `./seal-secrets.sh`.
4. Commit only Git-tracked manifest changes and `apps/third-party/postiz/postiz-secrets.sealed.yaml`.
