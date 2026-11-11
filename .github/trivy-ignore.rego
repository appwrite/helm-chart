# Findings of `trivy config` on the rendered ci/ scenarios that are by design.
# Each exception names its rules and the one resource they may flag, matched
# in the finding's message, so the same rule still fires anywhere else.
package trivy

import rego.v1

default ignore := false

exceptions := [
	# The Docker daemon must be a privileged root container with a writable root
	# filesystem; seccomp doesn't apply to privileged containers (docs/executor.md).
	{
		"ids": {"KSV-0001", "KSV-0012", "KSV-0014", "KSV-0017"},
		"resource": "Container 'dind' of Deployment 'appwrite-executor'",
	},
	{
		"ids": {"KSV-0104"},
		"resource": `container "dind" of deployment "appwrite-executor"`,
	},
	{
		"ids": {"KSV-0118"},
		"resource": "deployment appwrite-executor in appwrite-executor namespace",
	},
	# The executor client runs as root without capabilities to use the daemon's
	# socket, which is root-equivalent whatever its user.
	{
		"ids": {"KSV-0012"},
		"resource": "Container 'executor' of Deployment 'appwrite-executor'",
	},
	# The orchestrator starts and deletes build Jobs, in the builds namespace only.
	{
		"ids": {"KSV-0048"},
		"resource": "Role 'appwrite-orchestrator'",
	},
	# Non-secret settings matched by name (ports, limits, usernames); secrets are
	# in the appwrite Secret.
	{
		"ids": {"KSV-01010"},
		"resource": "ConfigMap 'appwrite-env' in 'appwrite' namespace",
	},
]

ignore if {
	some exception in exceptions
	input.ID in exception.ids
	startswith(input.Message, exception.resource)
}
