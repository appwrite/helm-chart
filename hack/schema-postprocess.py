#!/usr/bin/env python3
"""Relax the generated values.schema.json for Kubernetes passthrough fields.

helm-values-schema-json infers a schema from the defaults in values.yaml and,
with noAdditionalProperties, closes every object. That is what we want for the
chart's own settings (typos fail fast), but fields that are passed straight to
Kubernetes (resources, affinity, tolerations, security contexts, ...) must
accept anything the Kubernetes API accepts. This script replaces the schema of
those keys, wherever they appear, with a permissive schema of the right type.

Usage: hack/schema-postprocess.py charts/appwrite/values.schema.json
"""
import json
import sys

QUANTITY_MAP = {"type": "object", "additionalProperties": {"type": ["string", "number"]}}

OBJECT = {"type": "object"}
OBJECT_LIST = {"type": "array", "items": {"type": "object"}}

PASSTHROUGH = {
    "resources": {
        "type": "object",
        "properties": {
            "requests": QUANTITY_MAP,
            "limits": QUANTITY_MAP,
            "claims": OBJECT_LIST,
        },
        "additionalProperties": False,
    },
    "affinity": OBJECT,
    "podSecurityContext": OBJECT,
    "containerSecurityContext": OBJECT,
    "updateStrategy": OBJECT,
    "behavior": OBJECT,
    "tolerations": OBJECT_LIST,
    "topologySpreadConstraints": OBJECT_LIST,
    "extraEnv": OBJECT_LIST,
    "extraEnvFrom": OBJECT_LIST,
    "extraVolumes": OBJECT_LIST,
    "extraVolumeMounts": OBJECT_LIST,
    "extraInitContainers": OBJECT_LIST,
    "extraContainers": OBJECT_LIST,
    "extraObjects": {"type": "array"},
}


def relax(node):
    if isinstance(node, dict):
        props = node.get("properties")
        if isinstance(props, dict):
            for key, schema in props.items():
                if key in PASSTHROUGH and isinstance(schema, dict):
                    replacement = dict(PASSTHROUGH[key])
                    for meta in ("description", "title", "default"):
                        if meta in schema:
                            replacement[meta] = schema[meta]
                    props[key] = replacement
                else:
                    relax(schema)
        for key, value in node.items():
            if key != "properties":
                relax(value)
    elif isinstance(node, list):
        for item in node:
            relax(item)


def main(path):
    with open(path) as f:
        schema = json.load(f)
    relax(schema)
    with open(path, "w") as f:
        json.dump(schema, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1])
