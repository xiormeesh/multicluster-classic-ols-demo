#!/usr/bin/env python3
"""List model IDs available to this demo's OpenAI API credential."""

import argparse
import json
import os
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen

API_KEY_ENV = "ONLY_OLS_OPENAI_API_KEY"
MODELS_URL = "https://api.openai.com/v1/models"


def list_model_ids(api_key: str) -> list[str]:
    """Fetch model IDs available to the API credential."""
    request = Request(
        MODELS_URL,
        headers={"Authorization": f"Bearer {api_key}"},
    )

    with urlopen(request, timeout=30) as response:
        payload = json.load(response)

    if not isinstance(payload, dict) or not isinstance(payload.get("data"), list):
        raise ValueError("the API response did not contain a model list")

    return sorted(
        model["id"]
        for model in payload["data"]
        if isinstance(model, dict) and isinstance(model.get("id"), str)
    )


def main() -> int:
    """List available models or check one model ID."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "model",
        nargs="?",
        help="check whether this model ID is listed",
    )
    args = parser.parse_args()

    api_key = os.environ.get(API_KEY_ENV)
    if not api_key:
        parser.error(f"{API_KEY_ENV} must be set")

    try:
        model_ids = list_model_ids(api_key)
    except HTTPError as error:
        print(f"error: model-list request returned HTTP {error.code}", file=sys.stderr)
        return 1
    except OSError:
        print("error: model-list request failed", file=sys.stderr)
        return 1
    except (json.JSONDecodeError, ValueError) as error:
        print(f"error: invalid model-list response: {error}", file=sys.stderr)
        return 1

    if args.model:
        if args.model in model_ids:
            print(f"{args.model}: available")
            return 0

        print(f"{args.model}: not listed", file=sys.stderr)
        return 1

    print("\n".join(model_ids))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
