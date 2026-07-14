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

## Meta: Facebook and Instagram

The Postiz Facebook and Instagram providers both use the same Meta app credentials:

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
2. Replace `youtube_client_id` and `youtube_client_secret` placeholders with the Google OAuth client credentials.
3. Run `./seal-secrets.sh`.
4. Commit only Git-tracked manifest changes and `apps/third-party/postiz/postiz-secrets.sealed.yaml`.
