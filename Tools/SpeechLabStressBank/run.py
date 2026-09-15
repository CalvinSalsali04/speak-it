#!/usr/bin/env python3
"""Validate and replay SpeechLab Stress Bank v1 against the production probe.

The bank is synthetic failure-discovery data, not gold data. This evaluator
therefore keeps raw evidence, native normalized output, and the lossy contract
projection separate. Ambiguous rows are reported outside the deterministic
agreement denominator.
"""

from __future__ import annotations

import argparse
import csv
from collections import Counter, defaultdict
from datetime import datetime
import hashlib
import itertools
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any
import zipfile
from zoneinfo import ZoneInfo


EVALUATOR_VERSION = "speechlab-stress-evaluator-1.0.0"
BANK_VERSION = "SpeechLab-Stress-Bank-v1"
BANK_FILE = "speakit_stress_bank_v1_10000.jsonl"
REQUIRED_ARCHIVE_FILES = {
    BANK_FILE,
    "coverage_summary.csv",
    "README.md",
    "sample_200.csv",
    "manifest.json",
    "COVERAGE-REPORT.md",
}
REFERENCE_INSTANT = "2026-08-03T10:00:00-04:00"
REFERENCE_DAY = (2026, 8, 3)
TORONTO = ZoneInfo("America/Toronto")

BASE_KEYS = {
    "ambiguity_state", "bank_version", "case_id", "category", "contract_hash",
    "difficulty", "entities", "expected_contract", "expected_item_count",
    "generator_version", "label_status", "length_band", "lineage", "phenomena",
    "phenomena_count", "provenance", "safety_class", "seed", "semantic_family",
    "structure_id", "temporal", "trusted_anchor", "use_for_product_accuracy",
    "utterance", "word_count",
}
ITEM_KEYS = {
    "action", "kind", "polarity", "status", "object", "date", "destination",
    "person", "time", "notes", "recurrence",
}

DATE_DAYS = {
    "today": (2026, 8, 3), "tonight": (2026, 8, 3),
    "this afternoon": (2026, 8, 3), "tomorrow": (2026, 8, 4),
    "tomorrow morning": (2026, 8, 4), "tomorrow afternoon": (2026, 8, 4),
    "tomorrow evening": (2026, 8, 4), "in two days": (2026, 8, 5),
    "in three days": (2026, 8, 6), "monday": (2026, 8, 3),
    "tuesday": (2026, 8, 4), "wednesday": (2026, 8, 5),
    "thursday": (2026, 8, 6), "friday": (2026, 8, 7),
    "saturday": (2026, 8, 8), "sunday": (2026, 8, 9),
    "next monday": (2026, 8, 10), "next friday": (2026, 8, 14),
    "the end of the month": (2026, 8, 31),
    "the first of next month": (2026, 9, 1),
    "october 12": (2026, 10, 12), "october 22": (2026, 10, 22),
}
DATE_TIME_BANDS = {
    "tonight": "evening", "this afternoon": "afternoon",
    "tomorrow morning": "morning", "tomorrow afternoon": "afternoon",
    "tomorrow evening": "evening",
}
AMBIGUOUS_DATES = {"next week", "this weekend"}
ACTION_EQUIVALENCE = [
    {"buy", "get", "grab", "pick up"},
    {"visit", "go", "go to"},
    {"cancel reminder", "cancel_reminder"},
    {"cancel intent", "cancel_intent", "do not need"},
]
NEGATIVE_MARKERS = {"not", "never", "dont", "don t", "do not", "avoid", "skip"}
ACTION_MARKERS = {
    "buy", "get", "grab", "pick up", "go", "visit", "return", "call", "text",
    "email", "send", "book", "attend", "check", "upload", "print", "apply",
    "cancel", "file", "reschedule", "review", "sign", "download", "renew",
    "pay", "finish", "update", "submit", "confirm", "scan", "drive",
}
CONTENT_STOP = {
    "a", "an", "the", "to", "at", "on", "in", "for", "about", "of", "my",
    "me", "i", "it", "that", "and", "then", "please", "remind",
}
GENERIC_CLUSTER_PHENOMENA = {
    "safety_critical", "clean_speech", "temporal", "multiple_items",
    "long_utterance", "asr_effect",
}
DIMENSION_NAMES = {
    "exact_structured_agreement", "expected_item_count", "over_splitting", "under_splitting",
    "lost_information", "invented_information", "wrong_routing", "title_corruption",
    "action_corruption", "object_corruption", "person_reference_error", "location_error",
    "date_error", "time_error", "recurrence_error", "correction_failure",
    "false_start_failure", "abandoned_thought_failure", "unfinished_clause_failure",
    "shared_context_failure", "ordering_failure", "negation_failure", "prohibition_failure",
    "cancellation_failure", "selective_cancellation_failure", "resolved_alternative_failure",
    "unresolved_alternative_mishandling", "conditional_intent_failure", "ambiguity_mishandling",
    "unsafe_positive_action", "trailing_noise_artifact",
}


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_text(value: Any) -> str:
    text = str(value or "").casefold().replace("’", "'")
    text = text.replace("don't", "do not").replace("can't", "cannot")
    return " ".join(re.findall(r"[a-z0-9]+", text))


def semantic_tokens(value: Any) -> list[str]:
    return [token for token in normalize_text(value).split() if token not in CONTENT_STOP]


def phrase_matches(phrase: str, text: str, threshold: float = 1.0) -> bool:
    wanted = semantic_tokens(phrase)
    if not wanted:
        return True
    present = set(semantic_tokens(text))
    return sum(token in present for token in wanted) / len(wanted) >= threshold


def action_variants(action: str) -> set[str]:
    normalized = normalize_text(action)
    if normalized in {"conditional task", "conditional reminder"}:
        return {normalized}
    for group in ACTION_EQUIVALENCE:
        normalized_group = {normalize_text(value) for value in group}
        if normalized in normalized_group:
            return normalized_group
    return {normalized}


def action_matches(action: str, text: str, expected_object: str = "") -> bool:
    normalized_text = f" {normalize_text(text)} "
    if action in {"conditional_task", "conditional_reminder"}:
        condition_kept = " if " in normalized_text or " unless " in normalized_text
        underlying = semantic_tokens(expected_object)
        return condition_kept and (not underlying or underlying[0] in normalized_text.split())
    return any(f" {variant} " in normalized_text for variant in action_variants(action))


def timestamp_projection(value: Any) -> Any:
    if value is None:
        return None
    local = datetime.fromtimestamp(float(value), TORONTO)
    return {
        "iso_toronto": local.isoformat(),
        "day": [local.year, local.month, local.day],
        "wall_clock": [local.hour, local.minute],
    }


def normalized_actual(actual: dict[str, Any]) -> dict[str, Any]:
    items = []
    for item in actual["items"]:
        projected = dict(item)
        for key in ("title", "quote", "rawQuote", "analysis", "person", "temporalSource"):
            projected[key + "Normalized"] = normalize_text(item.get(key))
        projected["dueNormalized"] = timestamp_projection(item.get("due"))
        projected["reminderNormalized"] = timestamp_projection(item.get("reminder"))
        items.append(projected)
    operations = [
        {**operation, "targetNormalized": normalize_text(operation.get("target"))}
        for operation in actual["operations"]
    ]
    return {"textNormalized": normalize_text(actual["text"]), "items": items, "operations": operations}


def clock_candidates(text: str) -> list[list[int]]:
    value = normalize_text(text)
    while value.startswith("after "):
        value = value[6:]
    if value in {"at noon", "around noon"}:
        return [[12, 0]]
    if value == "in two hours":
        return [[12, 0]]
    match = re.search(r"(?:at|around) (\d{1,2})(?: (\d{1,2}))?$", value)
    if not match:
        return []
    hour, minute = int(match.group(1)), int(match.group(2) or 0)
    candidates = [[hour % 24, minute]]
    if 1 <= hour <= 11:
        candidates.append([hour + 12, minute])
    return candidates


def normalized_expected(contract: dict[str, Any]) -> dict[str, Any]:
    result = []
    for item in contract.get("items", []):
        projected = {key: value for key, value in item.items()}
        for key in ("action", "object", "destination", "person", "date", "time", "recurrence", "notes"):
            if key in item:
                projected[key + "Normalized"] = normalize_text(item[key])
        if "date" in item:
            date_text = normalize_text(item["date"])
            projected["expectedDay"] = list(DATE_DAYS[date_text]) if date_text in DATE_DAYS else None
            projected["expectedTimeBand"] = DATE_TIME_BANDS.get(date_text)
            projected["dateIsAmbiguous"] = date_text in AMBIGUOUS_DATES
        if "time" in item:
            projected["wallClockCandidates"] = clock_candidates(item["time"])
        result.append(projected)
    return {"items": result}


def archive_rows(bank_path: Path) -> tuple[bytes, dict[str, bytes]]:
    if bank_path.suffix.casefold() == ".zip":
        with zipfile.ZipFile(bank_path) as archive:
            names = set(archive.namelist())
            if names != REQUIRED_ARCHIVE_FILES:
                raise ValueError(f"Archive members differ: expected {sorted(REQUIRED_ARCHIVE_FILES)}, got {sorted(names)}")
            if any(Path(name).name != name for name in names):
                raise ValueError("Archive contains a path instead of flat immutable bank files")
            files = {name: archive.read(name) for name in names}
        return files[BANK_FILE], files
    if bank_path.name != BANK_FILE:
        raise ValueError(f"Expected {BANK_FILE} or its ZIP archive")
    data = bank_path.read_bytes()
    return data, {BANK_FILE: data}


def count_coverage(rows: list[dict[str, Any]]) -> dict[str, Any]:
    categories = Counter(row["category"] for row in rows)
    safety = Counter(row["safety_class"] for row in rows)
    ambiguity = Counter(row["ambiguity_state"] for row in rows)
    lengths = Counter(row["length_band"] for row in rows)
    difficulties = Counter(row["difficulty"] for row in rows)
    phenomenon_counts = Counter(p for row in rows for p in row["phenomena"])
    structures = Counter(row["structure_id"] for row in rows)
    return {
        "category_counts": dict(categories), "safety_counts": dict(safety),
        "ambiguity_counts": dict(ambiguity), "length_distribution": dict(lengths),
        "difficulty_distribution": dict(difficulties),
        "semantic_family_count": len({row["semantic_family"] for row in rows}),
        "structure_id_count": len(structures),
        "phenomenon_label_count": len(phenomenon_counts),
        "largest_structure_share": max(structures.values()) / len(rows),
    }


def validate_bank(bank_path: Path) -> tuple[list[dict[str, Any]], dict[str, Any], dict[str, Any], dict[str, bytes]]:
    data, files = archive_rows(bank_path)
    try:
        lines = data.decode("utf-8").splitlines()
        rows = [json.loads(line) for line in lines if line.strip()]
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"Invalid UTF-8 JSONL: {error}") from error
    manifest = json.loads(files["manifest.json"]) if "manifest.json" in files else {}
    errors: list[str] = []
    if len(rows) != 10_000:
        errors.append(f"expected 10000 rows, found {len(rows)}")
    ids = [row.get("case_id") for row in rows]
    utterances = [row.get("utterance") for row in rows]
    expected_ids = [f"SB10K-{number:05d}" for number in range(1, 10_001)]
    if ids != expected_ids:
        errors.append("case IDs are not the stable ordered SB10K-00001..SB10K-10000 sequence")
    if len(set(ids)) != len(ids):
        errors.append("case IDs are not unique")
    if len(set(utterances)) != len(utterances):
        errors.append("utterances are not exactly unique")
    for index, row in enumerate(rows, 1):
        allowed_keys = BASE_KEYS | ({"acceptable_contracts"} if "acceptable_contracts" in row else set())
        if set(row) != allowed_keys:
            errors.append(f"row {index} has inconsistent root keys")
        if row.get("bank_version") != BANK_VERSION:
            errors.append(f"row {index} has wrong bank version")
        if row.get("expected_item_count") != len(row.get("expected_contract", {}).get("items", [])):
            errors.append(f"row {index} expected item count does not match contract")
        if row.get("phenomena_count") != len(row.get("phenomena", [])):
            errors.append(f"row {index} phenomenon count does not match labels")
        if any(set(item) - ITEM_KEYS for item in row.get("expected_contract", {}).get("items", [])):
            errors.append(f"row {index} contains an unknown expected-item key")
        digest = sha256_bytes(canonical_json(row.get("expected_contract")).encode())[:20]
        if digest != row.get("contract_hash"):
            errors.append(f"row {index} contract hash mismatch")
        if row.get("safety_class") not in {"ordinary", "safety_critical"}:
            errors.append(f"row {index} has invalid safety classification")
        if row.get("ambiguity_state") not in {"none", "requires_review"}:
            errors.append(f"row {index} has invalid ambiguity classification")
        expected_types = {
            "case_id": str, "utterance": str, "category": str, "semantic_family": str,
            "structure_id": str, "phenomena": list, "entities": dict, "temporal": dict,
            "expected_contract": dict, "expected_item_count": int, "word_count": int,
            "phenomena_count": int, "trusted_anchor": bool, "use_for_product_accuracy": bool,
        }
        if any(not isinstance(row.get(key), kind) for key, kind in expected_types.items()):
            errors.append(f"row {index} has a field with the wrong JSON type")
        if any(not isinstance(item, dict) for item in row.get("expected_contract", {}).get("items", [])):
            errors.append(f"row {index} has a non-object expected item")
        if "acceptable_contracts" in row and row.get("ambiguity_state") != "requires_review":
            errors.append(f"row {index} has alternatives without requires_review")
        if not isinstance(row.get("utterance"), str) or not row["utterance"].strip() or "\n" in row["utterance"]:
            errors.append(f"row {index} has an invalid utterance")
        if len(errors) >= 25:
            break
    jsonl_hash = sha256_bytes(data)
    if manifest:
        if manifest.get("case_count") != len(rows):
            errors.append("manifest case count mismatch")
        if manifest.get("sha256_jsonl") != jsonl_hash:
            errors.append("manifest JSONL hash mismatch")
        if manifest.get("exact_unique_utterances") != len(set(utterances)):
            errors.append("manifest utterance uniqueness mismatch")
        coverage = count_coverage(rows)
        for key in (
            "category_counts", "safety_counts", "ambiguity_counts", "length_distribution",
            "difficulty_distribution", "semantic_family_count", "structure_id_count",
            "phenomenon_label_count",
        ):
            if manifest.get(key) != coverage[key]:
                errors.append(f"manifest {key} mismatch")
        if abs(float(manifest.get("largest_structure_share", -1)) - coverage["largest_structure_share"]) > 0.00001:
            errors.append("manifest largest structure share mismatch")
    if "sample_200.csv" in files:
        sample = list(csv.DictReader(files["sample_200.csv"].decode("utf-8").splitlines()))
        by_id = {row["case_id"]: row for row in rows}
        if len(sample) != 200 or len({row["case_id"] for row in sample}) != 200:
            errors.append("sample_200.csv does not contain 200 unique rows")
        for sample_row in sample:
            full = by_id.get(sample_row["case_id"])
            if not full or json.loads(sample_row["contract_json"]) != full["expected_contract"]:
                errors.append(f"sample row {sample_row['case_id']} does not match JSONL")
                break
    if "coverage_summary.csv" in files:
        supplied = {
            (entry["dimension"], entry["value"]): int(entry["count"])
            for entry in csv.DictReader(files["coverage_summary.csv"].decode("utf-8").splitlines())
        }
        computed: dict[tuple[str, str], int] = {}
        for dimension, source in (
            ("category", Counter(row["category"] for row in rows)),
            ("safety_class", Counter(row["safety_class"] for row in rows)),
            ("ambiguity_state", Counter(row["ambiguity_state"] for row in rows)),
            ("length_band", Counter(row["length_band"] for row in rows)),
            ("phenomenon", Counter(value for row in rows for value in row["phenomena"])),
            ("semantic_family", Counter(row["semantic_family"] for row in rows)),
        ):
            computed.update({(dimension, value): count for value, count in source.items()})
        if supplied != computed:
            errors.append("coverage_summary.csv does not match JSONL counts")
    if errors:
        raise ValueError("Bank validation failed:\n- " + "\n- ".join(errors))
    validation = {
        "status": "passed", "row_count": len(rows), "unique_case_ids": len(set(ids)),
        "unique_utterances": len(set(utterances)), "contract_hashes_verified": len(rows),
        "expected_item_counts_verified": len(rows), "schema_variants": 2,
        "optional_acceptable_contract_rows": sum("acceptable_contracts" in row for row in rows),
        "jsonl_sha256": jsonl_hash, "archive_sha256": sha256_file(bank_path),
        **count_coverage(rows),
    }
    return rows, manifest, validation, files


def actual_item_text(item: dict[str, Any]) -> str:
    return " ".join(str(item.get(key) or "") for key in ("title", "analysis"))


def field_similarity(expected: dict[str, Any], actual: dict[str, Any]) -> float:
    text = actual_item_text(actual)
    score = 0.0
    for key, weight in (("action", 2.0), ("object", 4.0), ("person", 3.0), ("destination", 3.0)):
        value = expected.get(key)
        if not value:
            continue
        matched = action_matches(value, text, expected.get("object", "")) if key == "action" else phrase_matches(value, text, .75)
        score += weight if matched else 0.0
    if expected.get("person") and normalize_text(actual.get("person")) == normalize_text(expected["person"]):
        score += 3.0
    return score


def best_alignment(expected: list[dict[str, Any]], actual: list[dict[str, Any]]) -> list[tuple[int, int]]:
    if not expected or not actual:
        return []
    # Bank captures are small; cap the factorial path defensively for malformed probe output.
    if max(len(expected), len(actual)) > 8:
        available = set(range(len(actual)))
        aligned = []
        for expected_index, item in enumerate(expected):
            if not available:
                break
            actual_index = max(available, key=lambda index: field_similarity(item, actual[index]))
            available.remove(actual_index)
            aligned.append((expected_index, actual_index))
        return aligned
    best: tuple[float, list[tuple[int, int]]] = (-1.0, [])
    if len(expected) <= len(actual):
        for chosen in itertools.permutations(range(len(actual)), len(expected)):
            pairs = list(enumerate(chosen))
            score = sum(field_similarity(expected[e], actual[a]) for e, a in pairs)
            if score > best[0]:
                best = (score, pairs)
    else:
        for chosen in itertools.permutations(range(len(expected)), len(actual)):
            pairs = [(chosen[a], a) for a in range(len(actual))]
            score = sum(field_similarity(expected[e], actual[a]) for e, a in pairs)
            if score > best[0]:
                best = (score, pairs)
    return best[1]


def expected_recurrence(value: str) -> dict[str, Any]:
    mapping = {
        "every day": ("daily", 1, []), "every other day": ("daily", 2, []),
        "every week": ("weekly", 1, []), "every two weeks": ("weekly", 2, []),
        "every weekday": ("weekly", 1, [2, 3, 4, 5, 6]),
        "every sunday evening": ("weekly", 1, [1]),
        "every monday": ("weekly", 1, [2]), "every friday": ("weekly", 1, [6]),
        "every month": ("monthly", 1, []),
        "on the first of every month": ("monthly", 1, []),
    }
    frequency, interval, weekdays = mapping[normalize_text(value)]
    return {"frequency": frequency, "interval": interval, "weekdays": weekdays}


def temporal_matches(expected: dict[str, Any], actual: dict[str, Any]) -> tuple[bool, bool]:
    date_ok, time_ok = True, True
    actual_days = []
    if actual.get("temporalDay"):
        day = actual["temporalDay"]
        actual_days.append([day["year"], day["month"], day["day"]])
    actual_clocks = []
    if actual.get("wallClock"):
        actual_clocks.append([actual["wallClock"]["hour"], actual["wallClock"]["minute"]])
    for field in ("due", "reminder"):
        projected = timestamp_projection(actual.get(field))
        if projected:
            actual_days.append(projected["day"])
            actual_clocks.append(projected["wall_clock"])
    date_text = normalize_text(expected.get("date"))
    if date_text:
        if date_text in DATE_DAYS:
            date_ok = list(DATE_DAYS[date_text]) in actual_days
        elif date_text in AMBIGUOUS_DATES:
            source = normalize_text(actual.get("temporalSource"))
            date_ok = actual.get("temporal") != "none" and (
                phrase_matches(date_text, source) or actual.get("needsReview") or actual.get("state") != "resolved"
            )
        else:
            date_ok = False
        band = DATE_TIME_BANDS.get(date_text)
        if band:
            if not actual_clocks:
                time_ok = False
            else:
                time_ok = any(
                    (band == "morning" and 5 <= hour < 12)
                    or (band == "afternoon" and 12 <= hour < 18)
                    or (band == "evening" and (hour >= 17 or hour < 4))
                    for hour, _ in actual_clocks
                )
    if expected.get("time"):
        candidates = clock_candidates(expected["time"])
        if candidates:
            time_ok = any(clock in candidates for clock in actual_clocks)
        else:
            # Event-shaped/fuzzy times are only credited when the native temporal
            # intent retains the phrase; a source quote by itself is not parsing.
            time_ok = actual.get("temporal") != "none" and phrase_matches(
                expected["time"], actual.get("temporalSource") or "", .75
            )
    return date_ok, time_ok


def recurrence_matches(expected: dict[str, Any], actual: dict[str, Any]) -> bool:
    if not expected.get("recurrence"):
        return True
    rule = actual.get("recurrenceRule")
    if not rule:
        return False
    wanted = expected_recurrence(expected["recurrence"])
    if any(rule.get(key) != value for key, value in wanted.items()):
        return False
    if normalize_text(expected["recurrence"]) == "on the first of every month":
        ordinal = rule.get("ordinalWeekday")
        # A first-of-month series is day-number anchored, not ordinal-weekday anchored.
        return ordinal is None
    return True


def compare_contract(row: dict[str, Any], actual: dict[str, Any], contract: dict[str, Any]) -> dict[str, Any]:
    expected = contract.get("items", [])
    got = actual.get("items", [])
    dimensions: set[str] = set()
    expected_count, actual_count = len(expected), len(got)
    if expected_count != actual_count:
        dimensions.add("expected_item_count")
        dimensions.add("over_splitting" if actual_count > expected_count else "under_splitting")
    alignment = best_alignment(expected, got)
    matched_expected = {e for e, _ in alignment}
    matched_actual = {a for _, a in alignment}
    if len(matched_expected) < expected_count:
        dimensions.add("lost_information")
    if len(matched_actual) < actual_count:
        dimensions.add("invented_information")
    if [a for _, a in sorted(alignment)] != sorted(a for _, a in alignment):
        dimensions.add("ordering_failure")
    item_projection = []
    for expected_index, actual_index in alignment:
        exp, item = expected[expected_index], got[actual_index]
        text = actual_item_text(item)
        projection: dict[str, Any] = {"expectedIndex": expected_index, "actualIndex": actual_index}
        if item.get("route") != "Today":
            dimensions.add("wrong_routing")
        action_ok = action_matches(exp.get("action", ""), text, exp.get("object", ""))
        projection["actionMatched"] = action_ok
        if not action_ok:
            dimensions.update(("action_corruption", "title_corruption"))
        for field, dimension, threshold in (
            ("object", "object_corruption", .75),
            ("destination", "location_error", .75),
        ):
            if exp.get(field):
                ok = phrase_matches(exp[field], text, threshold)
                projection[field + "Matched"] = ok
                if not ok:
                    dimensions.update((dimension, "title_corruption"))
        if exp.get("person"):
            person_ok = (
                normalize_text(item.get("person")) == normalize_text(exp["person"])
                or phrase_matches(exp["person"], text)
            )
            projection["personMatched"] = person_ok
            if not person_ok:
                dimensions.add("person_reference_error")
        date_ok, time_ok = temporal_matches(exp, item)
        projection.update(dateMatched=date_ok, timeMatched=time_ok)
        if not date_ok:
            dimensions.add("date_error")
        if not time_ok:
            dimensions.add("time_error")
        recurrence_ok = recurrence_matches(exp, item)
        projection["recurrenceMatched"] = recurrence_ok
        if not recurrence_ok:
            dimensions.add("recurrence_error")
        title_norm = f" {normalize_text(item.get('title'))} "
        if exp.get("polarity") == "negative" and not any(marker in title_norm for marker in NEGATIVE_MARKERS):
            dimensions.add("negation_failure")
        notes = normalize_text(exp.get("notes"))
        if "destination unspecified not " in notes or "keep cancel destination " in notes:
            forbidden = notes.split(" not ", 1)[1] if " not " in notes else notes.split("destination ", 1)[1]
            if phrase_matches(forbidden, item.get("title") or "", .75):
                dimensions.add("location_error")
        if exp.get("action") in {"conditional_task", "conditional_reminder"}:
            if item.get("state") == "resolved" and not (" if " in title_norm or " unless " in title_norm):
                dimensions.add("conditional_intent_failure")
        item_projection.append(projection)
    utterance_tokens = set(semantic_tokens(row["utterance"]))
    for item in got:
        quote_tokens = set(semantic_tokens(item.get("quote")))
        if quote_tokens - utterance_tokens and not item.get("wasRepaired"):
            dimensions.add("invented_information")
    base_mismatch = bool(dimensions)
    phenomena = set(row["phenomena"])
    derived = {
        "correction_failure": bool(phenomena & {"correction", "date_correction", "time_correction", "action_correction", "destination_correction"}),
        "false_start_failure": "false_start" in phenomena,
        "abandoned_thought_failure": bool(phenomena & {"abandoned_thought", "explicit_abandonment", "full_abandonment"}),
        "unfinished_clause_failure": bool(phenomena & {"unfinished_clause", "incomplete_restart"}),
        "shared_context_failure": bool(phenomena & {"shared_context", "shared_temporal_context", "shared_object"}),
        "negation_failure": False,
        "prohibition_failure": False,
        "cancellation_failure": bool(
            phenomena & {"cancellation", "cancel_reminder_request", "cancellation_scope"}
            and dimensions & {"expected_item_count", "lost_information", "invented_information"}
        ),
        "selective_cancellation_failure": "selective_cancellation" in phenomena,
        "resolved_alternative_failure": "resolved_alternative" in phenomena,
        "unresolved_alternative_mishandling": False,
        "conditional_intent_failure": False,
        "trailing_noise_artifact": "trailing_conversational_noise" in phenomena,
    }
    if base_mismatch:
        dimensions.update(name for name, applies in derived.items() if applies)
    unsafe = unsafe_positive_action(row, expected, got, actual.get("operations", []), alignment, dimensions)
    if unsafe:
        dimensions.add("unsafe_positive_action")
        if "negation" in phenomena:
            dimensions.add("negation_failure")
        if "prohibition" in phenomena:
            dimensions.add("prohibition_failure")
    return {
        "dimensions": sorted(dimensions), "alignment": item_projection,
        "expectedCount": expected_count, "actualCount": actual_count,
        "unsafePositiveAction": unsafe,
    }


def unsafe_positive_action(
    row: dict[str, Any], expected: list[dict[str, Any]], actual: list[dict[str, Any]],
    operations: list[dict[str, Any]],
    alignment: list[tuple[int, int]], dimensions: set[str],
) -> bool:
    if row["safety_class"] != "safety_critical":
        return False
    def negative(text: str) -> bool:
        padded = f" {normalize_text(text)} "
        return any(f" {normalize_text(marker)} " in padded for marker in NEGATIVE_MARKERS | {"forget"})

    def actionable(item: dict[str, Any]) -> bool:
        padded = f" {normalize_text(item.get('title'))} "
        return item.get("route") == "Today" and any(f" {marker} " in padded for marker in ACTION_MARKERS)

    for expected_index, actual_index in alignment:
        exp, item = expected[expected_index], actual[actual_index]
        title = f" {normalize_text(item.get('title'))} "
        if exp.get("polarity") == "negative" and not negative(title):
            return True
        if exp.get("action") in {"conditional_task", "conditional_reminder"}:
            if actionable(item) and " if " not in title and " unless " not in title:
                return True
        notes = normalize_text(exp.get("notes"))
        if "destination unspecified not " in notes:
            forbidden = notes.split(" not ", 1)[1]
            if phrase_matches(forbidden, title, .75):
                return True
    phenomena = set(row["phenomena"])
    if not expected and phenomena & {"explicit_abandonment", "full_abandonment"}:
        return any(actionable(item) and not negative(item.get("title") or "") for item in actual)
    if not expected and "cancel_reminder_request" in phenomena:
        has_cancel_operation = any(operation.get("operation") == "cancel" for operation in operations)
        return not has_cancel_operation and any(actionable(item) and not negative(item.get("title") or "") for item in actual)

    utterance = row["utterance"].casefold().replace("’", "'")
    cancelled_targets = []
    for pattern in (
        r"actually\s+skip\s+(.+?)(?:[.,;]|$)",
        r"actually\s+forget\s+(?:that|the\s+)?(.+?)(?:[.,;]|$)",
        r"do\s+not\s+go\s+to\s+(.+?)(?:[;,]|$)",
    ):
        cancelled_targets.extend(match.group(1) for match in re.finditer(pattern, utterance))
    operation_targets = " ".join(
        normalize_text(operation.get("target")) for operation in operations
        if operation.get("operation") in {"cancel", "retract"}
    )
    for target in cancelled_targets:
        if phrase_matches(target, operation_targets, .75):
            continue
        for item in actual:
            if actionable(item) and phrase_matches(target, item.get("title") or "", .75) and not negative(item.get("title") or ""):
                return True
    return False


def choose_comparison(row: dict[str, Any], actual: dict[str, Any]) -> dict[str, Any]:
    contracts = [row["expected_contract"], *row.get("acceptable_contracts", [])]
    comparisons = [compare_contract(row, actual, contract) for contract in contracts]
    comparison = min(comparisons, key=lambda value: (len(value["dimensions"]), value["unsafePositiveAction"]))
    comparison["matchedContractIndex"] = comparisons.index(comparison)
    if row["ambiguity_state"] == "requires_review":
        uncertain = any(item.get("needsReview") or item.get("state") != "resolved" for item in actual["items"])
        if not comparison["dimensions"]:
            result = "allowed_interpretation"
        elif uncertain and not comparison["unsafePositiveAction"]:
            result = "uncertainty_preserved"
            comparison["dimensions"] = [
                dimension for dimension in comparison["dimensions"]
                if dimension not in {"ambiguity_mishandling", "unresolved_alternative_mishandling"}
            ]
        else:
            result = "requires_review_mismatch"
            comparison["dimensions"] = sorted(set(comparison["dimensions"]) | {"ambiguity_mishandling"})
        comparison["ambiguityOutcome"] = result
    else:
        result = "exact_structured_agreement" if not comparison["dimensions"] else "disagreement"
    comparison["result"] = result
    return comparison


def subsystem_for(dimensions: list[str]) -> str:
    dims = set(dimensions)
    if "unsafe_positive_action" in dims or dims & {"negation_failure", "cancellation_failure", "prohibition_failure", "selective_cancellation_failure"}:
        return "safety_scope"
    if dims & {"over_splitting", "under_splitting", "ordering_failure", "shared_context_failure"}:
        return "clause_segmentation"
    if dims & {"date_error", "time_error", "recurrence_error"}:
        return "temporal_parser"
    if dims & {"person_reference_error", "location_error"}:
        return "reference_location"
    if dims & {"correction_failure", "false_start_failure", "abandoned_thought_failure", "unfinished_clause_failure"}:
        return "speech_repair"
    if dims & {"wrong_routing"}:
        return "organization_routing"
    if dims & {"action_corruption", "object_corruption", "title_corruption", "lost_information", "invented_information"}:
        return "title_semantics"
    if dims & {"ambiguity_mishandling", "conditional_intent_failure", "unresolved_alternative_mishandling"}:
        return "semantic_state"
    return "mixed_or_unknown"


def priority_for(record: dict[str, Any]) -> str:
    dims = set(record["mismatch_dimensions"])
    if "unsafe_positive_action" in dims:
        return "P0"
    if record["safety_class"] == "safety_critical" and dims:
        return "P1"
    if dims & {"lost_information", "invented_information", "wrong_routing", "action_corruption", "object_corruption", "negation_failure", "cancellation_failure"}:
        return "P1"
    if dims & {"over_splitting", "under_splitting", "date_error", "time_error", "recurrence_error", "person_reference_error", "location_error", "shared_context_failure"}:
        return "P2"
    return "P3"


def cluster_label(record: dict[str, Any]) -> str:
    phenomena = [p.replace("_", " ") for p in record["phenomena"] if p not in GENERIC_CLUSTER_PHENOMENA]
    dimensions = [d.replace("_", " ") for d in record["mismatch_dimensions"] if d not in {
        "title_corruption", "expected_item_count", "lost_information", "invented_information",
    }]
    left = " + ".join(phenomena[:4]) or record["semantic_family"].replace(".", " ")
    right = ", ".join(dimensions[:4]) or "structured disagreement"
    return f"{left}: {right}"


def root_cluster(record: dict[str, Any]) -> tuple[str, str]:
    phenomena, dims = set(record["phenomena"]), set(record["mismatch_dimensions"])
    if "unsafe_positive_action" in dims:
        if phenomena & {"explicit_abandonment", "full_abandonment"}:
            return "unsafe_full_abandonment", "Full abandonment leaves an earlier positive action active"
        if "conditional_intent" in phenomena:
            return "unsafe_conditional", "Condition detached from an actionable reminder"
        if "selective_cancellation" in phenomena:
            return "unsafe_selective_cancellation", "Selective cancellation leaves the withdrawn destination/action active"
        if "negation" in phenomena:
            return "unsafe_asr_negation", "ASR 'not two' split turns a negative call into a positive action"
        return "unsafe_other", "Other unsafe positive action"
    if record["ambiguity_state"] == "requires_review":
        return "ambiguity", "Explicitly ambiguous capture handling"
    if dims & {"cancellation_failure"} and record["actual_production_output"].get("operations"):
        return "operation_representation", "Bank item contract versus native cancellation operation"
    if "trailing_noise_artifact" in dims:
        return "trailing_noise", "Trailing conversational noise becomes an extra row or corrupts a title"
    if "selective_cancellation" in phenomena:
        return "selective_cancellation", "Selective cancellation mismatch without an unsafe positive action"
    if phenomena & {"destination_correction", "resolved_alternative"}:
        return "destination_correction", "Corrected or resolved destination is split away from its action"
    if phenomena & {"object_correction", "abandoned_thought"} and "correction_failure" in dims:
        return "superseded_correction", "Superseded action/object survives a correction"
    if "false_start_failure" in dims or "unfinished_clause_failure" in dims:
        return "false_start", "False start or unfinished restart creates extra structure"
    if "shared_context_failure" in dims and "shared_temporal_context" in phenomena:
        return "shared_temporal", "Shared temporal context is detached or unevenly propagated across items"
    if "shared_context_failure" in dims and "reference_resolution" in phenomena:
        return "reference_chain", "Pronoun or shared-object chain is merged or loses its antecedent"
    if "over_splitting" in dims and record["semantic_family"].startswith(("clean.errand", "wrapper.errand")):
        return "composite_errand", "One destination-plus-purchase errand is decomposed into multiple rows"
    if record["semantic_family"] == "clean.appointment" and dims <= {"action_corruption", "title_corruption"}:
        return "appointment_projection", "Appointment noun phrase disagrees only with bank's implicit 'attend' action"
    if "recurrence_error" in dims:
        return "recurrence", "Recurrence contract is missing or structurally different"
    if "time_error" in dims:
        return "time", "Clock, fuzzy-time, or corrected-time mismatch"
    if "date_error" in dims:
        return "date", "Date or date-correction mismatch"
    if "person_reference_error" in dims or "location_error" in dims:
        return "reference_location", "Person, destination, or location association mismatch"
    if "wrong_routing" in dims:
        return "routing", "Today/Memory routing mismatch"
    if "over_splitting" in dims:
        return "over_split", "Other over-splitting"
    if "under_splitting" in dims:
        return "under_split", "Other under-splitting"
    if dims & {"action_corruption", "object_corruption", "title_corruption"}:
        return "content_projection", "Action/object/title semantic projection mismatch"
    return "other", cluster_label(record)


def build_clusters(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    labels: dict[str, str] = {}
    for record in records:
        if not record["mismatch_dimensions"]:
            continue
        key, label = root_cluster(record)
        grouped[key].append(record)
        labels[key] = label
    priority_rank = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
    clusters = []
    for number, (key, members) in enumerate(grouped.items(), 1):
        priorities = Counter(member["priority"] for member in members)
        priority = min(priorities, key=priority_rank.get)
        structures = Counter(member["structure_id"] for member in members)
        families = Counter(member["semantic_family"] for member in members)
        item_counts = Counter(str(member["expected_item_count"]) for member in members)
        length_bands = Counter(member["length_band"] for member in members)
        phenomena = Counter(value for member in members for value in member["phenomena"])
        dimensions = Counter(value for member in members for value in member["mismatch_dimensions"])
        subsystems = Counter(member["likely_subsystem"] for member in members)
        sample = members[:3]
        confidence = "low" if any(m["ambiguity_state"] == "requires_review" for m in members) else (
            "high" if all(m["difficulty"] in {"easy", "medium"} for m in members) else "medium"
        )
        clusters.append({
            "cluster_id": f"CL-{number:04d}", "root_key": key, "label": labels[key],
            "case_count": len(members), "bank_percentage": round(100 * len(members) / 10_000, 3),
            "priority": priority, "safety_relevant": any(m["safety_class"] == "safety_critical" for m in members),
            "unsafe_positive_count": sum(m["unsafe_positive_action"] for m in members),
            "semantic_families": dict(families.most_common()),
            "expected_item_counts": dict(item_counts.most_common()),
            "length_bands": dict(length_bands.most_common()),
            "phenomena": dict(phenomena.most_common()),
            "failure_dimensions": dict(dimensions.most_common()),
            "likely_production_subsystems": dict(subsystems.most_common()),
            "expected_contract_confidence": confidence,
            "structure_ids": dict(structures.most_common()),
            "representative_examples": [
                {
                    "case_id": m["case_id"], "utterance": m["utterance"],
                    "expected": m["expected_contract"],
                    "actual": m["actual_production_output"],
                } for m in sample
            ],
        })
    clusters.sort(key=lambda c: (priority_rank[c["priority"]], -c["unsafe_positive_count"], -c["case_count"], c["label"]))
    for index, cluster in enumerate(clusters, 1):
        cluster["rank"] = index
    return clusters


def counter_by(records: list[dict[str, Any]], key: str) -> dict[str, dict[str, int]]:
    total = Counter()
    failing = Counter()
    for record in records:
        values = record[key] if isinstance(record[key], list) else [record[key]]
        for value in values:
            total[value] += 1
            if record["mismatch_dimensions"]:
                failing[value] += 1
    return {value: {"cases": total[value], "failing": failing[value]} for value in sorted(total)}


def safety_breakdown(records: list[dict[str, Any]]) -> dict[str, Any]:
    safety = [record for record in records if record["safety_class"] == "safety_critical"]
    requested = {
        "negation": {"negation"}, "prohibitive_reminders": {"prohibition"},
        "dont_forget": {"dont_forget_positive_intent"}, "cancellation": {"cancellation"},
        "full_abandonment": {"full_abandonment", "explicit_abandonment"},
        "partial_cancellation": {"partial_cancellation"}, "selective_cancellation": {"selective_cancellation"},
        "replacing_an_action": {"replacement", "action_correction"},
        "negative_state_changes": {"negative_state_change"}, "temporal_negation": {"negated_old_time", "temporal_scope"},
        "location_negation": {"location_scope"}, "unresolved_alternatives": {"unresolved_alternative"},
        "conditional_intent": {"conditional_intent"}, "cancellation_scope": {"cancellation_scope"},
    }
    breakdown = {}
    for name, phenomena in requested.items():
        cohort = [record for record in safety if phenomena & set(record["phenomena"])]
        breakdown[name] = {
            "cases": len(cohort), "disagreements": sum(bool(record["mismatch_dimensions"]) for record in cohort),
            "unsafe_positive_actions": sum(record["unsafe_positive_action"] for record in cohort),
        }
    return {
        "cases": len(safety), "exact_or_allowed": sum(not record["mismatch_dimensions"] for record in safety),
        "disagreements": sum(bool(record["mismatch_dimensions"]) for record in safety),
        "unsafe_positive_actions": sum(record["unsafe_positive_action"] for record in safety),
        "breakdown": breakdown,
    }


def summarize(records: list[dict[str, Any]], clusters: list[dict[str, Any]], metadata: dict[str, Any]) -> dict[str, Any]:
    deterministic = [record for record in records if record["ambiguity_state"] == "none"]
    ambiguous = [record for record in records if record["ambiguity_state"] == "requires_review"]
    dimensions = Counter(dimension for record in records for dimension in record["mismatch_dimensions"])
    dimensions["exact_structured_agreement"] = sum(not record["mismatch_dimensions"] for record in records)
    for name in DIMENSION_NAMES:
        dimensions[name] += 0
    ambiguity = Counter(record["comparison_result"] for record in ambiguous)
    exact = sum(record["comparison_result"] == "exact_structured_agreement" for record in deterministic)
    disagreements = len(deterministic) - exact
    return {
        "interpretation": "Synthetic stress-bank disagreement is failure-discovery evidence, not real-world Speak It accuracy.",
        "bank": metadata, "case_count": len(records), "deterministic_case_count": len(deterministic),
        "exact_structured_agreement_count": exact, "disagreement_count": disagreements,
        "stress_bank_disagreement_rate": round(disagreements / len(deterministic), 6),
        "dimension_counts": dict(dimensions.most_common()),
        "ambiguity": {"cases": len(ambiguous), **dict(ambiguity)},
        "safety": safety_breakdown(records),
        "by_semantic_family": counter_by(records, "semantic_family"),
        "by_phenomenon": counter_by(records, "phenomena"),
        "by_structure": counter_by(records, "structure_id"),
        "priority_counts": dict(Counter(record["priority"] for record in records if record["mismatch_dimensions"])),
        "cluster_count": len(clusters), "top_20_clusters": clusters[:20],
    }


def run_git(root: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=root, text=True, capture_output=True, check=True).stdout.strip()


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run_probe(probe: Path, rows: list[dict[str, Any]], output: Path) -> list[dict[str, Any]]:
    inputs = "\n".join(row["utterance"] for row in rows) + "\n"
    (output / "inputs.txt").write_text(inputs, encoding="utf-8")
    started = time.monotonic()
    process = subprocess.run(
        [str(probe.resolve()), "--json"], input=inputs, text=True,
        capture_output=True, check=True, timeout=1800,
    )
    if process.stderr.strip():
        (output / "probe.stderr.txt").write_text(process.stderr, encoding="utf-8")
    actual = [json.loads(line) for line in process.stdout.splitlines() if line.strip()]
    if len(actual) != len(rows):
        raise ValueError(f"Probe returned {len(actual)} rows for {len(rows)} inputs")
    if [item["text"] for item in actual] != [row["utterance"] for row in rows]:
        raise ValueError("Probe output is missing, duplicated, or reordered")
    actual_path = output / "actual.jsonl"
    actual_path.write_text("".join(canonical_json(item) + "\n" for item in actual), encoding="utf-8")
    (output / "elapsed_seconds.txt").write_text(f"{time.monotonic() - started:.3f}\n", encoding="utf-8")
    return actual


def reuse_actual(path: Path, rows: list[dict[str, Any]], output: Path) -> list[dict[str, Any]]:
    actual = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(actual) != len(rows):
        raise ValueError(f"Cached actual output has {len(actual)} rows for {len(rows)} inputs")
    if [item["text"] for item in actual] != [row["utterance"] for row in rows]:
        raise ValueError("Cached probe output is missing, duplicated, or reordered")
    destination = output / "actual.jsonl"
    if path.resolve() != destination.resolve():
        shutil.copy2(path, destination)
    return actual


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bank", type=Path, required=True, help="Original bank ZIP or JSONL")
    parser.add_argument("--output", type=Path, required=True, help="Ignored result directory")
    parser.add_argument("--probe", type=Path, help="Existing PipelineProbe binary")
    parser.add_argument("--build-probe", action="store_true", help="Build current production probe first")
    parser.add_argument("--reuse-actual", type=Path, help="Reuse a previously verified actual.jsonl; never reruns the parser")
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()

    script = Path(__file__).resolve()
    root = script.parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    rows, manifest, validation, _ = validate_bank(args.bank.resolve())
    write_json(output / "validation.json", validation)
    if args.validate_only:
        print(json.dumps(validation, indent=2))
        return
    if args.build_probe:
        subprocess.run([str(root / "Tools/PipelineProbe/build.sh")], cwd=root, check=True)
    probe = (args.probe or root / "Tools/PipelineProbe/build/probe").resolve()
    if not probe.is_file():
        parser.error("Probe does not exist; pass --build-probe or --probe")

    git_head = run_git(root, "rev-parse", "HEAD")
    git_branch = run_git(root, "branch", "--show-current")
    status = run_git(root, "status", "--short")
    parser_paths = [
        root / "SpeakIt/Repositories", root / "SpeakIt/Models",
        root / "Tools/PipelineProbe/main.swift", root / "Tools/PipelineProbe/shims.swift",
        root / "Tools/PipelineProbe/build.sh",
    ]
    parser_digest = hashlib.sha256()
    for path in parser_paths:
        files = sorted(path.rglob("*.swift")) if path.is_dir() else [path]
        for file in files:
            parser_digest.update(str(file.relative_to(root)).encode())
            parser_digest.update(file.read_bytes())
    metadata = {
        "bank_name": manifest.get("bank_name", "SpeechLab Stress Bank v1"),
        "bank_version": manifest.get("bank_version", BANK_VERSION), "bank_seed": manifest.get("seed"),
        "bank_archive_sha256": validation["archive_sha256"], "bank_jsonl_sha256": validation["jsonl_sha256"],
        "parser_git_commit": git_head, "parser_git_branch": git_branch,
        "working_tree_dirty": bool(status), "working_tree_status": status.splitlines(),
        "parser_source_sha256": parser_digest.hexdigest(), "probe_sha256": sha256_file(probe),
        "evaluator_version": EVALUATOR_VERSION, "evaluator_sha256": sha256_file(script),
        "reference_instant": REFERENCE_INSTANT, "timezone": "America/Toronto",
        "environment": {"platform": platform.platform(), "python": platform.python_version(), "swift": subprocess.run(["swift", "--version"], text=True, capture_output=True).stdout.splitlines()[0]},
    }
    frozen_probe = output / "probe"
    if probe.resolve() != frozen_probe.resolve():
        shutil.copy2(probe, frozen_probe)
    write_json(output / "run-metadata.json", metadata)
    actual_rows = reuse_actual(args.reuse_actual.resolve(), rows, output) if args.reuse_actual else run_probe(probe, rows, output)
    records = []
    results_path = output / "results.jsonl"
    with results_path.open("w", encoding="utf-8") as handle:
        for row, actual in zip(rows, actual_rows):
            comparison = choose_comparison(row, actual)
            record = {
                "case_id": row["case_id"], "utterance": row["utterance"],
                "expected_contract": row["expected_contract"],
                "acceptable_contracts": row.get("acceptable_contracts", []),
                "actual_production_output": actual,
                "normalized_expected_output": normalized_expected(row["expected_contract"]),
                "normalized_actual_output": normalized_actual(actual),
                "comparison_result": comparison["result"],
                "mismatch_dimensions": comparison["dimensions"],
                "comparison_projection": comparison["alignment"],
                "matched_contract_index": comparison["matchedContractIndex"],
                "semantic_family": row["semantic_family"], "phenomena": row["phenomena"],
                "structure_id": row["structure_id"], "category": row["category"],
                "safety_class": row["safety_class"], "ambiguity_state": row["ambiguity_state"],
                "expected_item_count": row["expected_item_count"], "actual_item_count": len(actual["items"]),
                "length_band": row["length_band"], "word_count": row["word_count"],
                "difficulty": row["difficulty"], "contract_hash": row["contract_hash"],
                "unsafe_positive_action": comparison["unsafePositiveAction"],
            }
            record["likely_subsystem"] = subsystem_for(record["mismatch_dimensions"])
            record["priority"] = priority_for(record)
            records.append(record)
            handle.write(canonical_json(record) + "\n")
    clusters = build_clusters(records)
    summary = summarize(records, clusters, metadata)
    write_json(output / "clusters.json", clusters)
    write_json(output / "summary.json", summary)
    artifacts = {}
    for name in ("validation.json", "run-metadata.json", "inputs.txt", "actual.jsonl", "results.jsonl", "clusters.json", "summary.json", "probe"):
        artifacts[name] = {"sha256": sha256_file(output / name), "bytes": (output / name).stat().st_size}
    write_json(output / "result-manifest.json", {"artifacts": artifacts})
    print(json.dumps({
        "case_count": summary["case_count"],
        "exact_structured_agreement_count": summary["exact_structured_agreement_count"],
        "disagreement_count": summary["disagreement_count"],
        "stress_bank_disagreement_rate": summary["stress_bank_disagreement_rate"],
        "unsafe_positive_actions": summary["safety"]["unsafe_positive_actions"],
        "output": str(output),
    }, indent=2))


if __name__ == "__main__":
    main()
