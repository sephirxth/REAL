extends Node2D


func _ready() -> void:
	EvidenceRecorder.set_dimension_mode("2d")
	VisualEvidenceCapture.set_dimension_mode("2d")
	RuntimeActionExecutor.set_dimension_mode("2d")
	EditModeController.set_dimension_mode("2d")
	EvidenceRecorder.set_visual_evidence_capture(VisualEvidenceCapture)
	var state := {"type": "fixture", "position": Vector2.ZERO, "health": 1}
	EvidenceRecorder.register_entity("Fixture", state)
	RuntimeActionExecutor.register_entity("Fixture", self, state)
	EvidenceRecorder.capture("SMOKE_READY", {"request_id": "smoke"})
	get_tree().quit()
