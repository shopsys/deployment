# Upgrade notes

## How to Upgrade

1. In `composer.json` upgrade `shopsys/deployment` to new version:
    ```diff
   - "shopsys/deployment": "~1.9.0",
   + "shopsys/deployment": "~1.12.0",
    ```
2. Run `composer update shopsys/deployment`
3. Check files in mentioned pull requests and if you have any of them extended in your project, apply changes manually

## Upgrade from v2.0.1 to v2.1.0

- clear Redis cache only once instead of at every container start ([#7](https://github.com/shopsys/deployment/pull/7/files))
    - phing target `clean-redis-storefront` is available from shopsys/framework v14.0.0
