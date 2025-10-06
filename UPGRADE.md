# Upgrade notes

## How to Upgrade

1. In `composer.json` upgrade `shopsys/deployment` to new version:
    ```diff
   - "shopsys/deployment": "~2.1.3",
   + "shopsys/deployment": "~3.0.0",
    ```
2. Run `composer update shopsys/deployment`
3. Check files in mentioned pull requests and if you have any of them extended in your project, apply changes manually

## Upgrade from v4.0.11 to v4.1.0

- enabled setting domain with postfix in URL ([#57](https://github.com/shopsys/deployment/pull/57))

## Upgrade from v4.0.10 to v4.0.11

- Respect IP whitelisting and HTTP auth for not production environment ([#56](https://github.com/shopsys/deployment/pull/56))

## Upgrade from v4.0.9 to v4.0.10

- Upgrade RabbitMQ ([#55](https://github.com/shopsys/deployment/pull/55))

## Upgrade from v4.0.8 to v4.0.9

- Update allowed IP address pools in nginx.yaml for `location ~ ^/resolve-friendly-url` if you are using custom IP address pools in your cluster
- Added Cloudflare support ([#54](https://github.com/shopsys/deployment/pull/54))

## Upgrade from v4.0.7 to v4.0.8

- Remove CPU request limits ([#53](https://github.com/shopsys/deployment/pull/53))

## Upgrade from v4.0.6 to v4.0.7

- Horizontal autoscaler for PHP-FPM now checks only PHP-FPM container ([#49](https://github.com/shopsys/deployment/pull/49))
- Update resource requests and limits by best practices ([#50](https://github.com/shopsys/deployment/pull/50))
- Add tolerations to Cron, RabbitMQ and Consumers to be able to run only on selected nodes ([#51](https://github.com/shopsys/deployment/pull/51))

## Upgrade from v4.0.5 to v4.0.6

- prepare prometheus exporters for Redis and RabbitMQ ([#48](https://github.com/shopsys/deployment/pull/48))

## Upgrade from v4.0.4 to v4.0.5

- optimize cpu and memory resources ([#47](https://github.com/shopsys/deployment/pull/47))

## Upgrade from v4.0.3 to v4.0.4

- Follow redirects when checking if domains is running ([#46](https://github.com/shopsys/deployment/pull/46))

## Upgrade from v4.0.2 to v4.0.3

- Minor improvements ([#45](https://github.com/shopsys/deployment/pull/45))
  - Containers are pulled only if are not already downloaded
  - You can now define your custom rabbitmq URL by `RABBITMQ_DOMAIN_HOSTNAME` variable
  - Storefront autoscaling is now managed separately by `MIN_STOREFRONT_REPLICAS` and `MAX_STOREFRONT_REPLICAS` variables

## Upgrade from v4.0.1 to v4.0.2

- Optimize Redis configuration ([#44](https://github.com/shopsys/deployment/pull/44))

## Upgrade from v4.0.0 to v4.0.1

- Do not log notice messages after PHP-FPM starts ([#42](https://github.com/shopsys/deployment/pull/42))
- Refactor consumers logging and restarting ([#43](https://github.com/shopsys/deployment/pull/43))

## Upgrade from v3.3.4 to v4.0.0

- Upgrade manifests for newer versions of kubernetes ([#39](https://github.com/shopsys/deployment/pull/39))
- upgrade rabbitmq ingress manifest ([#40](https://github.com/shopsys/deployment/pull/40))
- enable logging for consumers ([#41](https://github.com/shopsys/deployment/pull/41))

## Upgrade from v3.3.3 to v3.3.4

- Check all domains at the end of deploy process ([#37](https://github.com/shopsys/deployment/pull/37))

## Upgrade from v3.3.2 to v3.3.3

- Fix problems with deployment ([#35](https://github.com/shopsys/deployment/pull/35))

## Upgrade from v3.3.1 to v3.3.2

- Redis was upgraded to version 7.4-alpine ([#34](https://github.com/shopsys/deployment/pull/34))
    - If you are using older Redis version then define `REDIS_VERSION='redis:7.0-alpine'` with using version in your `deploy-project.sh` file

## Upgrade from v3.3.0 to v3.3.1

- Finding running container for after deploy tasks is fixed ([#33](https://github.com/shopsys/deployment/pull/33))

## Upgrade from v3.2.9 to v3.3.0

- Cron can run under Alpine Linux ([#31](https://github.com/shopsys/deployment/pull/31))

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
