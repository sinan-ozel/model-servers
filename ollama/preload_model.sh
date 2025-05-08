#!/bin/bash

# Issue a dummy prompt to trigger model loading.
echo "What is 2 + 2?" | ollama run "$MODEL_NAME:$MODEL_TAG"
