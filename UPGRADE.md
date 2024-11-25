# Upgrade notes

## How to Upgrade

1. In `composer.json` upgrade `shopsys/deployment` to new version:
    ```diff
   - "shopsys/deployment": "~2.1.3",
   + "shopsys/deployment": "~3.0.0",
    ```
2. Run `composer update shopsys/deployment`
3. Check files in mentioned pull requests and if you have any of them extended in your project, apply changes manually

## Upgrade from v3.2.7 to v3.2.9

- Added routes to Nginx ([Commit](https://github.com/shopsys/deployment/commit/5b378a3ee1131fed8ac2821158f03f667db19dcb))
- `RunAsUser` was removed from Kubernetes manifests ([#30](https://github.com/shopsys/deployment/pull/30))

## Upgrade from v3.2.6 to v3.2.7

- upgraded PHP-FPM and Nginx configuration ([#29](https://github.com/shopsys/deployment/pull/29))
  - If you are using `shopsys/kubernetes-buildpack:1.1` in your Gitlab CI pipeline, update it to `shopsys/kubernetes-buildpack:1.2`
  - This upgrade will work only with kubectl client in version 1.25+ (Upgraded in `shopsys/kubernetes-buildpack:1.2`)

## Upgrade from v3.2.5 to v3.2.6

- blocked dynamic content on CDN now returns 403 code ([#27](https://github.com/shopsys/deployment/pull/27))

## Upgrade from v3.2.4 to v3.2.5

- returns only static content from vshosting CDN ([#25](https://github.com/shopsys/deployment/pull/25))

## Upgrade from v3.2.3 to v3.2.4

- nginx app location for customer uploaded file added ([#21](https://github.com/shopsys/deployment/pull/21))

## Upgrade from v3.2.2 to v3.2.3

- implemented script to send slack notification about deployment process ([#23](https://github.com/shopsys/deployment/pull/23))
- updated fpm workers and set terminate timeout ([#24](https://github.com/shopsys/deployment/pull/24))

## Upgrade from v3.2.1 to v3.2.2

- upgraded nginx to version 1.27.0 ([#21](https://github.com/shopsys/deployment/pull/21))

## Upgrade from v3.2.0 to v3.2.1

- consumer manifests are created properly for the first deploy ([#20](https://github.com/shopsys/deployment/pull/20))

## Upgrade from v3.1.0 to v3.2.0

- upgraded PHP-FPM and Nginx configuration ([#19](https://github.com/shopsys/deployment/pull/19))

## Upgrade from v3.0.4 to v3.1.0

- added social-network url for redirecting to backend ([#17](https://github.com/shopsys/deployment/pull/17))

## Upgrade from v3.0.3 to v3.0.4

- Warmup Symfony cache after start php container ([#18](https://github.com/shopsys/deployment/pull/18))

## Upgrade from v3.0.0 to v3.0.1

- fix incorrect order of redirect requests ([#15](https://github.com/shopsys/deployment/pull/15))

## Upgrade from v2.1.3 to v3.0.0

- refactor working with whitelisted IP addresses ([#11](https://github.com/shopsys/deployment/pull/11))
- fix redirect chain ([#12](https://github.com/shopsys/deployment/pull/12))
- correctly call self domain from container ([#13](https://github.com/shopsys/deployment/pull/13))
- improve configuration for Redis ([#14](https://github.com/shopsys/deployment/pull/14))

## Upgrade from v2.1.2 to v2.1.3

- added security headers for more safety ([#10](https://github.com/shopsys/deployment/pull/10))

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
