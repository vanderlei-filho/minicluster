#!/bin/bash

# MPI Cluster Management Script
# Usage: ./cluster.sh [command] [options]

set -e

COMPOSE_FILE="docker-compose.yml"
DOCKERFILE="base/amazon_linux.Dockerfile"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_usage() {
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  build             Build the MPI container image"
    echo "  up [workers]      Start cluster with specified number of workers (default: 3)"
    echo "  down              Stop and remove all containers"
    echo "  scale [workers]   Scale cluster to specified number of workers"
    echo "  exec [container]  Execute bash in specified container (default: mpi-master)"
    echo "                    Use 'master', 'worker', 'worker-1', 'worker-2', etc."
    echo "  logs [container]  Show logs for specified container"
    echo "  ps                Show running containers"
    echo "  clean             Remove all containers and images"
    echo "  hostfile          Generate MPI hostfile"
    echo "  test              Run MPI test (single and multi-container)"
    echo "  ssh-test          Test SSH connectivity between containers"
    echo ""
    echo "Examples:"
    echo "  $0 up 5           Start cluster with 5 worker nodes"
    echo "  $0 exec worker    Shell into first worker node"
    echo "  $0 exec worker-2  Shell into second worker node"
    echo "  $0 test           Run MPI hello world test"
}

build_image() {
    echo -e "${BLUE}Building MPI container image...${NC}"
    docker build -f $DOCKERFILE -t mpi-amazonlinux .
    echo -e "${GREEN}Build complete!${NC}"
}

start_cluster() {
    local workers=${1:-3}
    echo -e "${BLUE}Starting MPI cluster with $workers workers...${NC}"
    docker-compose up -d --scale mpi-worker=$workers
    echo -e "${GREEN}Cluster started!${NC}"
    show_status
}

stop_cluster() {
    echo -e "${BLUE}Stopping MPI cluster...${NC}"
    docker-compose down
    echo -e "${GREEN}Cluster stopped!${NC}"
}

scale_cluster() {
    local workers=${1:-3}
    echo -e "${BLUE}Scaling cluster to $workers workers...${NC}"
    docker-compose up -d --scale mpi-worker=$workers
    echo -e "${GREEN}Scaling complete!${NC}"
    show_status
}

exec_container() {
    local container=${1:-"mpi-master"}
    if [[ $container == "master" ]]; then
        container="mpi-master"
    elif [[ $container =~ ^worker-?([0-9]+)?$ ]]; then
        if [[ $container == "worker" ]]; then
            container=$(docker ps --format "{{.Names}}" | grep "mpi-worker" | head -1)
            if [[ -z $container ]]; then
                echo -e "${RED}No worker containers found${NC}"
                return 1
            fi
        else
            worker_num=$(echo $container | grep -o '[0-9]\+')
            container=$(docker ps --format "{{.Names}}" | grep "mpi-worker" | sed -n "${worker_num}p")
            if [[ -z $container ]]; then
                echo -e "${RED}Worker $worker_num not found${NC}"
                return 1
            fi
        fi
    elif [[ ! $container =~ ^mpi- ]]; then
        container="mpi-$container"
    fi

    echo -e "${BLUE}Executing bash in $container...${NC}"
    docker exec -it $container /bin/bash
}

show_logs() {
    local container=${1:-"mpi-master"}
    if [[ $container == "master" ]]; then
        container="mpi-master"
    elif [[ $container =~ ^worker-[0-9]+$ ]]; then
        container="mpi-$container"
    elif [[ ! $container =~ ^mpi- ]]; then
        container="mpi-$container"
    fi

    docker logs $container
}

show_status() {
    echo -e "${BLUE}MPI Cluster Status:${NC}"
    docker-compose ps
}

clean_all() {
    echo -e "${YELLOW}Cleaning up all containers and images...${NC}"
    docker-compose down --rmi all --volumes
    echo -e "${GREEN}Cleanup complete!${NC}"
}

generate_hostfile() {
    echo -e "${BLUE}Generating MPI hostfile...${NC}"
    mkdir -p ./shared
    cat > ./shared/hostfile << EOF
# MPI Hostfile - Generated $(date)
# Format: hostname slots=N
mpi-master slots=1
EOF
    for container in $(docker ps --format "{{.Names}}" | grep "mpi.*worker" | sort); do
        echo "$container slots=1" >> ./shared/hostfile
    done
    echo -e "${GREEN}Hostfile created at ./shared/hostfile${NC}"
    echo "Contents:"
    cat ./shared/hostfile
}

run_mpi_test() {
    echo -e "${BLUE}Running MPI test...${NC}"
    echo "Waiting for SSH to be ready..."
    sleep 3

    cat > ./shared/test_mpi.c << 'EOF'
#include <mpi.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char** argv) {
    MPI_Init(&argc, &argv);
    int rank, size;
    char hostname[256];
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    gethostname(hostname, sizeof(hostname));
    printf("Hello from rank %d of %d on %s\n", rank, size, hostname);
    MPI_Finalize();
    return 0;
}
EOF

    generate_hostfile

    echo "Compiling MPI test program..."
    docker exec mpi-master bash -c "cd /shared && mpicc test_mpi.c -o test_mpi"

    echo -e "${YELLOW}Running single-container MPI test (4 processes):${NC}"
    docker exec mpi-master bash -c "cd /shared && mpirun --allow-run-as-root -np 4 ./test_mpi"

    total_slots=$(docker exec mpi-master bash -c "cd /shared && grep -c 'slots=1' hostfile")

    if [ "$total_slots" -gt 1 ]; then
        echo -e "${YELLOW}Running multi-container MPI test ($total_slots processes, 1 per container):${NC}"
        docker exec mpi-master bash -c "cd /shared && mpirun --allow-run-as-root --hostfile hostfile --map-by ppr:1:node -np $total_slots ./test_mpi"
    else
        echo -e "${YELLOW}Only one container available for testing${NC}"
    fi
}

test_ssh_connectivity() {
    echo -e "${BLUE}Testing SSH connectivity between containers...${NC}"
    sleep 3
    containers=$(docker ps --format "{{.Names}}" | grep "mpi" | sort)
    echo "Available containers:"
    echo "$containers"
    echo ""

    echo -e "${YELLOW}Testing SSH from mpi-master to workers:${NC}"
    for container in $containers; do
        if [[ $container != "mpi-master" ]]; then
            echo -n "  $container: "
            result=$(docker exec mpi-master ssh -o ConnectTimeout=5 $container "hostname" 2>/dev/null)
            if [[ $? -eq 0 ]]; then
                echo -e "${GREEN}✅ Connected ($result)${NC}"
            else
                echo -e "${RED}❌ Failed${NC}"
            fi
        fi
    done
    echo -e "${GREEN}SSH connectivity test complete!${NC}"
}

# Main script logic
case ${1:-""} in
    "build") build_image ;;
    "up") start_cluster $2 ;;
    "down") stop_cluster ;;
    "scale") scale_cluster $2 ;;
    "exec") exec_container $2 ;;
    "logs") show_logs $2 ;;
    "ps") show_status ;;
    "clean") clean_all ;;
    "hostfile") generate_hostfile ;;
    "test") run_mpi_test ;;
    "ssh-test") test_ssh_connectivity ;;
    "help"|"--help"|"-h") print_usage ;;
    "") print_usage ;;
    *) echo -e "${RED}Unknown command: $1${NC}"; print_usage; exit 1 ;;
esac
