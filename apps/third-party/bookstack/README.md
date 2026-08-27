# BookStack

BookStack is the review workspace for Hermes agent drafts. It is available at
`https://bookstack.nmajor.net`.

## Initial secret setup

1. Populate `bookstack-secrets.secret` locally. It is gitignored and must never
   be committed.
2. Generate `app-key` with:

   ```bash
   printf 'base64:%s' "$(openssl rand -base64 32)"
   ```

3. Use distinct high-entropy values for `database-password` and `root-password`.
4. Generate the encrypted manifest with `./seal-secrets.sh`.
5. Commit `bookstack-secrets.sealed.yaml`, never the `.secret` file.

## Agent workflow

Create a separate BookStack API user for each Hermes agent, restrict it to its
own BookStack book, and use that user's API token. Agents should link to the
BookStack draft from Discord instead of posting its full contents there.

The BookStack page is the source of truth for the draft and review comments.
