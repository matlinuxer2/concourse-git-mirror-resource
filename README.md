# concourse-git-mirror-resource

Mirror the branches between git repositories.



## Features

- Multiple repositories pull sources
- Multiple repositories push destinations
- Branch name filter with include and exclude regexp patterns
- Support prefix and postfix branch name renaming

## Source Configuration

Sample configuration:

```yaml
  source:
    private_key: |
      -----BEGIN RSA PRIVATE KEY-----
      MIIEowIBAAKCAQEAtCS10/f7W7lkQaSgD/mVeaSOvSF9ql4hf/zfMwfVGgHWjj+W
      <Lots more text>
      DWiJL+OFeg9kawcUL6hQ8JeXPhlImG6RTUffma9+iGQyyBMCGd1l
      -----END RSA PRIVATE KEY-----
    pull:
      - uri: https://some_git_hosting/abc.git
        include:
          - "^master$"
          - "^testing$"
          - "^features-.*$"
        rename:
          method: copy
      - uri: https://some_git_hosting/xyz.git
        include:
          - "^testing$"
          - "^feature-.*$"
        exclude:
          - "^master$"
        rename:
          method: copy
        collision: "overwrite"
      - uri: https://some_git_hosting/pqr.git
        include:
          - "^testing$"
          - "^feature-.*$"
        rename:
          method: prefix
          arg: "pqr-staging/"
        collision: "skip"
    push:
      - uri: ssh://git@git_hosting_for_developer/source.git
        force: true
        prune: "deleted"
      - uri: ssh://git@git_hosting_for_autobuild/source.git
        force: true
        prune: "all"
      - uri: ssh://git@git_hosting_for_backup/source.git
        force: true
        prune: "none"
```



- `private_key`: *Optional.* Private key to use when pulling/pushing.

- `pull`: List of repositories's configurations for pulling
  - `pull[].uri`: The URI of repository to mirror from
  - `pull[].include` : List of regexp patterns to include branches. Use the syntax of ``grep -e``.
  - `pull[].exclude` : List of regexp patterns to exclude branches. Use the syntax of ``grep -e``
  - `pull[].rename.method`: Choose how to transform branches' name.
    - ``copy``: Just copy the branches' name without any modification.
    - ``prefix``: Add a string in the beginning of the original branch name.
    - ``postfix``: Append a string in the end of the origininal branch name.
  - `pull[].rename.arg`: The argument used for `pull[].rename.method`
  - `pull[].collision`: Choose how to do when branches' name conflict
    - ``skip``: Don't overwrite previously created branches of the same name.
    - ``overwrite``: Overwrite previously created branches of the same name.

- `push`: List of repositories's configurations for pushing
  - `push[].uri`
  - `push[].force`
  - `push[].prune`
    - ``none``: Don't delete any remote branches.
    - ``delete``: Only delete remote branches which was mirror-pushed and currently deleted.
    - ``all``: Delete all orphan branches which having no corresponding local branches.

## Behavior


### `check`: Check and mirror branches

WARNING: This is NOT READ-ONLY resource in `check` state. I strongly recommend to have a backup or test with an experimental repository before deploying to real targets.

This resource will fetch the whole repository but only calculate the target branches based on include and exclude filters and branches renaming afterward.
When target branches status change -- added, deleted, or having new commits -- , the status calculation changes and generate a new version.
The version number itself just a simply hash value, not any git revision or so.


Unlike most other concourse resources keep read-only in `check` action, this one will do `git push` operations while `check` action.
The major reason is to utilize the concourse resource's cache mechanism without fetching git repositories repeatly for just a small commit.

### `in`: Do nothing


### `out`: Not supported.