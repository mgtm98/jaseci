# JAC Scale Deployment Guide

## Overview

`jac scale` is a Kubernetes deployment plugin for JAC applications. It automates the deployment process by building Docker images, pushing them to DockerHub, and creating Kubernetes resources for your application and required databases.

## Parameters

### Required environment variables

| Parameter | Description |
|-----------|-------------|
| `APP_NAME` | Name of your JAC application |


### Optional environment variables

| Parameter | Description | Default |
|-----------|-------------|---------|
| `DOCKER_USERNAME` | DockerHub username for pushing the image |
| `DOCKER_PASSWORD` | DockerHub password or access token |
| `K8_NAMESPACE` | Kubernetes namespace to deploy the application | - |
| `K8_NODE_PORT` | NodePort to expose the service | - |
| `K8_MONGODB` | Whether MongoDB is needed (`True`/`False`) | `False` |
| `K8_REDIS` | Whether Redis is needed (`True`/`False`) | `False` |

## How to run jac scale

Navigate to your JAC application folder:
```bash
cd /path/to/your/jac/app
```

Run the scale command:
```bash
jac scale <filename>
```

**Example:**
```bash
jac scale littlex.jac
```
## Deployment Modes

### Mode 1: Deploy Without Building (Default)
Deploys your JAC application to Kubernetes without building docker image.

```bash
jac scale littlex.jac
```

**Use this when:**
- You want faster deployments without rebuilding
- You're testing configuration changes

### Mode 2: Build, Push, and Deploy
Builds a new Docker image, pushes it to Docker Hub, then deploys to Kubernetes.

```bash
jac scale littlex.jac -b
```

**Requirements for Build Mode:**
- A `Dockerfile` in your application directory
- Environment variables set:
  - `DOCKER_USERNAME` - Your Docker Hub username
  - `DOCKER_PASSWORD` - Your Docker Hub password/access token

**Use this when:**
- In production settings.
- Build and host docker image.

## Architecture

### k8 pods structure
![k8 pod structure](diagrams/kubernetes-architecture.png)

## Important Notes

### Implementation

- The entire `jac scale` plugin is implemented using **Python and Kubernetes python client libraries**
- **No custom Kubernetes controllers** are used → easier to deploy and maintain

### Database Provisioning

- Databases are created as **StatefulSets** with persistent storage
- Databases are **only created on the first run**
- Subsequent `jac scale` calls only update application deployments
- This ensures persistent storage and avoids recreating databases unnecessarily

### Performance

- **First-time deployment** may take longer due to database provisioning and image downloading
- **Subsequent deployments** are faster since:
  - Only the application's final Docker layer is pushed and pulled
  - Only deployments are updated (databases remain unchanged)

## Steps followed by jac scale

### 1. Create JAC Application Docker Image

- Build the application image from the source directory
- Tag the image with DockerHub repository

### 2. Push Docker Image to DockerHub

- Authenticate using `DOCKER_USERNAME` and `DOCKER_PASSWORD`
- Push the image to DockerHub
- Subsequent pushes are faster since only the final image layer is pushed


### 3. Deploy application in k8

The plugin automatically:

- Creates Kubernetes Deployments for the JAC application
- Spawns necessary databases (MongoDB, PostgreSQL, Redis) as StatefulSets if requested
- Configures networking and service exposure

## Troubleshooting

- Ensure you have proper Kubernetes cluster access configured
- Verify DockerHub credentials are correct
- Check that the specified namespace exists or will be created
- For database connection issues, verify StatefulSets are running: `kubectl get statefulsets -n <namespace>`

## Future steps

- Caching of [base image](jac_scale/kubernetes/templates/base.Dockerfile) for quick deployment
- Enable autoscaling capability
- Auto creation of dockerfile using base image if not found
- Auto deletion of created k8 resources

## Things completed

- Deploy jac application using jac serve from jac core not jac-cloud
- Running jac application by
  1. by creating docker container and pushing to docker hub and then pull it and deploy it
  2. build pods at runtime using kubectl copy by using base image python3.12
- Auto spawning and connecting Databases like Redis and mongodb and connecting to jac deployment
- Populating env variables to jac application pods
- Files required for auto horizontal scaling

## Things ongoing

- Implementing memory hierachy by overriding Memory class using Redis and Mongodb similar to shelf storage used in Jac core(jusail)
- Converting walkers to api fastapi endpoints like server.py (walker)
- Implementation of fastapi implementation similar to server.py in Jac core
- Implementing execution contet in jac scale to support memory hierachy 

## Things todo

- Support JWT token in jac scale
- Merging running fastapi application and also deploying jac application in k8
- Current implementation uses parent folder of  file to deploy the jac application.It should be converted to identify only modules required to run jac application
- Enable horizontal autoscaling

## Testcases missed
- Test cases to test docker image build.currently we are only testing the k8 deploy part