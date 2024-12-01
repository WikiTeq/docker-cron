# WikiTeq Cron Docker Image

<div align="center">
  <img src="WikiTeq-docker-cron.webp" alt="WikiTeq Cron Mascot" width="300">
</div>

This is a Docker-based job scheduler that allows you to define and run cron jobs in Docker containers. It uses [Supercronic](https://github.com/aptible/supercronic) as the job runner to provide a flexible, reliable, and easy-to-configure cron experience.

## Key Features
- **Cron-Like Syntax**: Define and schedule tasks using familiar cron syntax.
- **Easy Configuration**: Define all your jobs using Docker labels, making configuration straightforward.
- **Logging**: Provides logging for all job executions, making monitoring and debugging simple.

## Getting Started

To start using this Docker image, you can create a `docker-compose.yml` configuration as shown in the example below.

### Example `docker-compose.yml`
```yaml
docker-compose.yml:

services:
  cron:
    image: ghcr.io/wikiteq/cron
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./logs/cron:/var/log/cron
    environment:
      - COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}
      - DEBUG=${CRON_DEBUG:-0}
      - TZ=America/New_York

  app:
    build: ./app
    container_name: app
    labels:
      cron.mytask.schedule: "* * * * *"
      cron.mytask.command: "/usr/local/bin/app_script.sh"
      cron.another_task.schedule: "*/2 * * * *"
      cron.another_task.command: "/usr/local/bin/another_app_script.sh"
```
This example shows how to schedule multiple cron jobs using cron syntax. The Docker container will run `/usr/local/bin/app_script.sh` every minute and `/usr/local/bin/another_app_script.sh` every two minutes, with logs stored in `/var/log/cron/`.

> **Note:** Ensure to mount the Docker socket (read-only mode) in your `docker-compose.yml` file to allow for proper interaction with Docker.

### Environment Variables
The `example_compose.yml` file uses several environment variables. Make sure to define these in a `.env` file in the root directory of your project:
- **`COMPOSE_PROJECT_NAME`**: Specifies the name of the Docker Compose project, allowing the cron to target jobs in that specific project. **Required**.
- **`DEBUG`**: Set to `true` to enable detailed output for debugging purposes.
- **`CRON_LOG_DIR`**: Defines the directory where cron stores log files for executed jobs, defaulting to `/var/log/cron`.
- **`TZ`**: The timezone used for scheduling cron jobs

### Volume Mounts
- **`/var/run/docker.sock`**: This is used to enable the Docker client inside the container to communicate with the Docker daemon running on the host. Be careful when using this as it provides elevated privileges.
- **`./logs/cron:/var/log/cron`**: Mount a directory to store the cron logs.

## Supercronic Integration

This image uses [Supercronic](https://github.com/aptible/supercronic) to run cron jobs in a more Docker-friendly way. Supercronic provides better logging, fewer overheads, and can be easily integrated with Docker containers, making it a better alternative to the traditional `cron` utility.

## Managing Cron Jobs

The image comes with several scripts to manage cron jobs:

- **`functions.sh`**: Contains helper functions for script operations.
- **`startup.sh`**: This script runs at container startup to initialize all required settings and start cron jobs.
- **`update_cron.sh`**: Used for updating cron jobs dynamically without restarting the container.

## Building and Running the Image

Pre-built Docker images are available for direct use. In the example, we use the latest version of the image: `ghcr.io/wikiteq/cron`. You can find all available images at: [WikiTeq Docker Cron Packages](https://github.com/WikiTeq/docker-cron/pkgs/container/cron).

To build the Docker image, use the following command:

```bash
docker build -t wikiteq/cron .
```
To run the Docker container, use:
```bash
docker run -d --name cron wikiteq/cron
```

Make sure to properly configure environment variables and volume mounts to suit your needs.

## Contributing
If you want to contribute to this project, please feel free to submit a pull request or open an issue on [GitHub](https://github.com/WikiTeq/docker-cron).

## Future Improvements
- **Non-Root User**: Modify the Dockerfile to run the container as a non-root user to enhance security and reduce potential risks.
- **Automated Testing**: Implement automated unit and integration testing to ensure code reliability and prevent issues during deployment.
- **Health Check Endpoint**: Add a health check mechanism to verify that cron jobs are running correctly and that the container is in a healthy state.

## Contact
For any questions or support, contact the maintainers at contact@wikiteq.com.
