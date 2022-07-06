package cmd

import (
	"tool/exec"
	"strings"
)

// A transform is a action that takes a input json and tranforms into a diff structure
#Transform: {
	after?: _

	input:  string
	output: string | *"test-temp.json"

	pipeline: string

	run: exec.Run & {
		$after: after

		cmd: ["bash", "-c", script]
		script: """
		set -ex

		jq -c < \(input) | jq '.' > \(output)
		"""
		// stdout: string
	}
}

// Verify schema runs `cue vet` on a .cue schema file with the option of a schema arg in addition.
#VerifySchema: {
	after?: _

	path:       string
	cue_schema: string
	schema:     string | *""

	command: [
		"cue vet",
		if schema != "" {
			"-d '\(schema)'"
		},

		cue_schema,
		path,
	]

	run: exec.Run & {
		$after: after
		cmd: ["bash", "-c", script]
		_cmd:   strings.Join(command, " ")
		script: """
		\(_cmd)
		"""
	}
}

// A schenario is a settings placefolder
#Scenario: {
	file: string

	cue_schema: string
	schema:     string
}

// #ScenarioGen takes
// files - List of sample files to be transformed
// schema - The CUELang schema to verify against
// cue_schema - The Alias / variable inside the CUELang schema file to check against
#ScenarioGen: {
	files: [...string]
	schema:     string
	cue_schema: string

	let _schema = schema
	let _cue_schema = cue_schema

	out: [
		for i in files {
			#Scenario & {
				file:       i
				schema:     _schema
				cue_schema: _cue_schema
			}
		},
	]
}

command: test_transforms: {
	myScenarios: (#ScenarioGen & {
		files: [
			"event.json",
		]

		cue_schema: "schema/*.cue"
		schema:     "#event"
	}).out

	scenarios: myScenarios

	transforms: {
		for scen in scenarios {
			let name = strings.Replace(scen.file, ".json", "", 1)

			"\(name)": (#Transform & {
				input:    "\(scen.file)"
				pipeline: "normalize.tremor"
				output:   "test-inner-\(name).json"
			}).run
		}
	}

	verifies: {
		for scen in scenarios {
			let name = strings.Replace(scen.file, ".json", "", 1)

			"\(name)": (#VerifySchema & {
				after: transforms[name].run

				path:       "test-inner-\(name).json"
				cue_schema: scen.cue_schema
				schema:     scen.schema
			}).run
		}
	}
}
