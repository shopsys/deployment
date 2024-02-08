# Upgrade notes

## How to Upgrade

1. In `composer.json` upgrade `shopsys/deployment` to new version:
    ```diff
   - "shopsys/deployment": "~1.9.0",
   + "shopsys/deployment": "~1.12.0",
    ```
2. Run `composer update shopsys/deployment`
3. Check files in mentioned pull requests and if you have any of them extended in your project, apply changes manually

## Upgrade from v2.1.1 to v2.1.2

- update your `deploy-project.sh` to properly deploy consumer manifests ([#9](https://github.com/shopsys/deployment/pull/9/files))

## Upgrade from v2.1.0 to v2.1.1

- check your custom `orchestration/kubernetes/kustomize/migrate-application/first-deploy/kustomization.yaml` file and update accordingly to the https://github.com/shopsys/deployment/commit/868bcb19e703170a15384504c5f1a2477be77c33

## Upgrade from v2.0.1 to v2.1.0

- clear Redis cache only once instead of at every container start ([#7](https://github.com/shopsys/deployment/pull/7/files))
    - phing target `clean-redis-storefront` is available from shopsys/framework v14.0.0

## Upgrade from v1.1.0 to v2.0.1

- use image proxy for images ([#5](https://github.com/shopsys/deployment/pull/5) and [#6](https://github.com/shopsys/deployment/pull/6))
    - the [`@imageResizer` PHP script](https://github.com/shopsys/shopsys/blob/14.0/project-base/app/web/imageResizer.php) is available from shopsys/project-base v14.0.0
    - be sure to verify the images redirection regex matches your application settings
        - all the image sizes are explicitly included in the regex so if your application uses another sizes, you need to update the regex to match your application settings
        - you might need to [create your own](https://github.com/shopsys/deployment#customize-deployment) storefront nginx config file for that purpose
