# 7. Publish without destroying what you did not create

- Status: accepted
- Date: 2026-09-01

## Context and Problem Statement

`publish-to-s3` uploads a build to a bucket this repository knows nothing
about. It does not know what else lives there, who else writes to it, how its
access is granted, or whether the distribution in front of it serves anything
else.

Four of its choices look like oversights under that ignorance, and a reader
who assumes a bucket dedicated to one project would tidy every one of them
away:

- it copies rather than syncing, so nothing is ever deleted
- it defaults to setting no object ACL
- it sets content types explicitly instead of letting the AWS CLI detect them
- it invalidates one prefix rather than the whole distribution

## Decision

Publishing touches only what it published. Anything broader is opt-in.

### Copy, never sync with delete

`aws s3 cp --recursive`, not `aws s3 sync --delete`.

A bucket commonly holds objects no repository produces — uploaded by hand,
left by an older process, or written by another project under another prefix.
A delete-enabled sync removes them, and nothing puts them back, because
nothing knows they existed.

Switching to `sync` is defensible only after enumerating what is under the
prefix and confirming every object is reproducible from a build.

### Default to no ACL

AWS has recommended disabling ACLs and granting access by bucket policy since
2023, and new buckets are created that way. The default follows the
recommendation rather than accommodating the older arrangement.

A bucket still in legacy `ObjectWriter` mode with no policy needs
`acl: public-read`. Omitting it there is a silent failure: the upload succeeds
and the objects are unreadable. That is why `public-base-url` also triggers a
check — one published file is fetched afterwards, and a non-200 fails the job.

So both mistakes are loud. Omitting a needed ACL fails the fetch; setting one
on a bucket with `BucketOwnerEnforced` fails with
`AccessControlListNotSupported`.

### Set content types explicitly

The AWS CLI infers a content type from the file extension. Its inference omits
the charset and has changed between CLI versions, so leaving it to the guess
means what a site serves can change for files nobody edited, at a time nobody
chose — including as a side effect of a runner image update.

### Invalidate the prefix, not the distribution

`/$PREFIX/*`, never `/*` unless the prefix is empty.

A distribution may serve several projects. A wildcard invalidation discards
every other project's cached objects, so their next requests all miss to the
origin, and CloudFront bills per invalidation path beyond the free tier.

An empty prefix is the exception: it means the bucket root, which is what a
project gets when the bucket is its own, and `/*` is then correct. The script
reports when that happens rather than doing it quietly.

## Scope

These are properties of the action, not of any bucket. Operational facts about
a particular bucket — its ownership mode, what unmanaged content it holds, the
order of a migration off ACLs — belong in the repository that publishes to it.
Recording them here would tie a generic action to one deployment and go stale
without anyone noticing.

## Consequences

Good:

- The action is safe to point at a bucket nobody has audited, which is the
  normal case for adoption.
- Each choice has a stated failure mode, so a reader can tell a defensive
  decision from a leftover.

Bad, and accepted:

- More conservative than a greenfield action would be. Someone publishing to a
  dedicated bucket with a policy and no unmanaged content carries defaults they
  do not need — though `acl`, `prefix` and `distribution-id` are all inputs, so
  the cost is configuration rather than a fork.
- Never deleting means a file dropped from a build stays published until
  someone removes it by hand. That is the deliberate trade: stale is
  recoverable, deleted is not.

## More Information

- `bin/publish-to-s3.sh` — the choices in the code
- [CHANGELOG.md](../../CHANGELOG.md) — when the ACL default changed, and why
