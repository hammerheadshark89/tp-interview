#!/usr/bin/python3

import argparse
import json
import random
import time
import urllib.request

VALID_PERIODS = ["Summer", "Autumn", "Winter", "Spring"]
VALID_HOTELS = ["FloatingPointResort", "GitawayHotel", "RecursionRetreat"]
VALID_ROOMS = ["SingletonRoom", "BooleanTwin", "RestfulKing"]

# Parse command-line arguments
parser = argparse.ArgumentParser(
    description="Run integration tests for dynamic pricing"
)
parser.add_argument(
    "--n", type=int, default=1, help="Number of iterations to run (default: 1)"
)
parser.add_argument(
    "--seed", type=int, default=42, help="Random seed for reproducibility (default: 42)"
)
parser.add_argument(
    "--max-sleep",
    type=int,
    default=0,
    help="Maximum sleep duration in seconds between calls (default: 0)",
)
args = parser.parse_args()

# Set seed for reproducible results
random.seed(args.seed)

# Run N iterations
for i in range(args.n):
    # Randomly select one combination
    period = random.choice(VALID_PERIODS)
    hotel = random.choice(VALID_HOTELS)
    room = random.choice(VALID_ROOMS)

    print(f"[Iteration {i+1}/{args.n}] Testing {period} {hotel} {room}")
    url = f"http://localhost:3000/pricing?period={period}&hotel={hotel}&room={room}"
    with urllib.request.urlopen(url) as response:
        data = json.loads(response.read().decode())
    print(data)

    # Sleep for a random duration between calls (except after the last iteration)
    if args.max_sleep > 0:
        sleep_duration = random.uniform(0, args.max_sleep)
        print(f"Sleeping for {sleep_duration:.2f} seconds...")
        time.sleep(sleep_duration)
