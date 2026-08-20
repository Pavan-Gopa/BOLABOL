#!/bin/bash
swift test --filter "Batch|Watched|Stability|Pipeline|Coordinator" > test_output.txt 2>&1
grep -A 10 "failed\." test_output.txt
