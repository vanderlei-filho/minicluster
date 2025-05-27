# Local Cluster Sandbox

This repository contains scripts, Dockerfiles, and Docker Compose YAML files to set up a local cluster of containers that can be used to emulate cloud instances.  
The `cluster.sh` script manages the lifecycle of the cluster and assumes a **1 MPI process per container (node)** mapping for simplified MPI testing and development.

---

## Features

- Build custom MPI container images based on Amazon Linux
- Spin up a cluster of MPI nodes (containers) locally using Docker Compose
- Scale the number of worker nodes dynamically
- Generate an MPI hostfile with one slot per container
- Run MPI hello world tests across one or multiple containers
- Test SSH connectivity between containers
- Clean up all containers and images

---

## Prerequisites

- Docker installed and running on your machine
- Docker Compose installed
- Basic understanding of MPI and containerization

---

## Usage

Run commands using the `cluster.sh` script:

```bash
./cluster.sh [command] [options]
```

---

## Examples

```bash
# Start a cluster with 5 worker nodes
./cluster.sh up 5

# Shell into the first worker container
./cluster.sh exec worker

# Shell into the third worker container
./cluster.sh exec worker-3

# Run the MPI hello world test
./cluster.sh test

# Generate MPI hostfile manually and view it
./cluster.sh hostfile
cat ./shared/hostfile

# Stop and remove the entire cluster
./cluster.sh down
```

---

## Running Your Own MPI Application

To run your own MPI application on this cluster:

1. Place your MPI source code and related files inside the ./shared directory on your host machine. This folder is mounted into all containers at runtime.

2. SSH into the master container or use docker exec to open a shell inside it:

   ```
   ./cluster.sh exec master
   ```

3. Inside the mpi-master container, navigate to /shared and compile your MPI program using mpicc or your preferred MPI compiler.

4. Run your MPI application with mpirun or mpiexec, using the provided hostfile in /shared/hostfile to span across the cluster nodes.

This setup ensures your application code is shared and accessible to all containers, enabling MPI communication between the nodes.
