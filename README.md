# Wikiteq cron docker image

It is a Docker-based job scheduler that allows you to define and run cron jobs in Docker containers.
It uses https://github.com/aptible/supercronic as the job runner

Key Features:
- **Cron-Like Syntax**: Similar to traditional cron jobs, you can define the schedule for each task using cron-like syntax.
- **Easy Configuration**: It uses the docker labels where you can define all your jobs.
- **Logging**: It provides logging of all job executions, making it easy to monitor and debug.

## Example

```yaml
services:
  cron:
    image: ghcr.io/wikiteq/cron
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./logs/cron:/var/log/cron
    environment:
      - COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}
      - DEBUG=${CRON_DEBUG:-0}
      - TZ=America/New_York

  app:
    build: ./app
    container_name: app
    labels:
      - cron.mytask.schedule="* * * * *"
      - cron.mytask.command="/usr/local/bin/app_script.sh"
      - cron.another_task.schedule="*/2 * * * *"
      - cron.another_task.command="/usr/local/bin/another_app_script.sh"
```

### Environment Variables

The `example_compose.yml` file uses several environment variables. Make sure to define these in a `.env` file in the root directory of your project:

- `COMPOSE_PROJECT_NAME`: if defined, the cron looks for the jobs in this compose project only
- `DEBUG`: when it is `true`, it outputs more iformation for debugging
- `CRON_LOG_DIR`: the directory where cron puts the log files of the executed jobs, `/var/log/cron` by default
- `TZ` timezone used for scheduling the cron jobs
