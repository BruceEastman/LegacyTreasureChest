"""A2 tests: Plan v2 request context, the strategy-specific prompt, and
checklist cleanup (identifiers, repeats, actions, closet-lot groups, repair).

Run from LTC_AI_Gateway/:
    .venv/bin/python -m unittest discover -s tests -v

Gemini is never called: the route's Gemini functions are stubbed per test.
"""

from __future__ import annotations

import copy
import json
import os
import unittest
import uuid
from unittest import mock

os.environ.setdefault("GEMINI_API_KEY", "test-dummy-key")
os.environ["LTC_DISABLE_ALL_AI"] = "false"
os.environ["LTC_DISABLE_GEMINI"] = "false"

from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402
from app.models_liquidation import LiquidationPlanRequest  # noqa: E402
from app.routes import analyze_item_photo as route  # noqa: E402
from app.services import gemini_client  # noqa: E402

RAW_IDS = ("pathA_maximizePrice", "pathB_delegateConsign", "pathC_quickExit", "needsInfo",
           "PathB_DelegateConsign", "Path B", "luxury_hub_mailin", "partnerType")


async def _no_network(*_args, **_kwargs):
    raise AssertionError("Tests must not call Gemini over the network.")


def _option(path, label, **kw):
    opt = {"id": str(uuid.uuid4()), "path": path, "label": label, "effort": "medium", "risks": []}
    opt.update(kw)
    return opt


CAMERA_BRIEF = {
    "schemaVersion": 1, "scope": "item", "generatedAt": "2026-10-16T00:00:00Z",
    "recommendedPath": "pathB_delegateConsign",
    "reasoning": "Collectors pay more through camera specialists.",
    "pathOptions": [
        _option("pathA_maximizePrice", "Sell online yourself", effort="high",
                netProceeds={"currencyCode": "USD", "low": 1300, "likely": 1500, "high": 1700}),
        _option("pathB_delegateConsign", "Specialist camera consignment",
                netProceeds={"currencyCode": "USD", "low": 1100, "likely": 1300, "high": 1500},
                timeEstimate="3 to 8 weeks", risks=["Commission of 20 to 30 percent"],
                logisticsNotes="Most specialists accept insured mail-in."),
        _option("pathC_quickExit", "Sell to a local camera shop", effort="low"),
    ],
    "actionSteps": ["Find a specialist"],
    "missingDetails": ["Whether the shutter fires accurately at all speeds"],
    "assumptions": ["Lens glass is clear", "Local fallback used"],
    "specialty": {"itemKind": "film camera", "detailTerms": ["rangefinder", "50mm lens"],
                  "brand": "Leica", "model": "M3", "isSpecialistItem": True},
}

# Exactly what app 1.2 sends.
V1_REQUEST = {
    "schemaVersion": 1, "scope": "item", "chosenPath": "pathB_delegateConsign",
    "brief": CAMERA_BRIEF, "title": "Leica M3 camera", "category": "Electronics",
}

ITEM_CONTEXT = {
    "description": "Leica M3 rangefinder with 50mm Summicron lens. Maker: Leica. Light brassing.",
    "quantity": 1, "unitValue": 1800, "currencyCode": "USD",
    "valuationLow": 1400, "valuationHigh": 2200, "valuationNotes": "Based on recent sales of M3 bodies.",
    "photoCount": 8, "documentCount": 1, "documentTypes": ["Receipt"], "hasAudioStory": True,
}


def _v2(**overrides) -> dict:
    req = copy.deepcopy(V1_REQUEST)
    req.update({
        "schemaVersion": 2,
        "selectedOption": CAMERA_BRIEF["pathOptions"][1],
        "isRecommended": True,
        "itemContext": ITEM_CONTEXT,
    })
    req.update(overrides)
    return req


def _prompt(request: dict) -> str:
    return route._build_liquidation_plan_prompt(LiquidationPlanRequest.model_validate(request))


def _plan_json(items, **kw) -> str:
    obj = {"schemaVersion": 2, "createdAt": "2026-10-16T00:00:00Z", "items": items}
    obj.update(kw)
    return json.dumps(obj)


def _step(text, **kw):
    s = {"order": 1, "text": text}
    s.update(kw)
    return s


CLOSET_SET_REQUEST = {
    "schemaVersion": 2, "scope": "set", "chosenPath": "pathB_delegateConsign",
    "brief": {**CAMERA_BRIEF, "scope": "set", "specialty": None},
    "title": "Mom's closet", "category": "Closet Lot",
    "setContext": {"setName": "Mom's closet", "setType": "Closet Lot", "completeness": "Complete",
                   "sellTogetherPreference": "SplitPreferred",
                   "story": "Closet Lot Metadata:\n• Brands: Chanel, J.Crew, Talbots",
                   "memberSummaries": []},
}


class _PlanRouteTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._net_patch = mock.patch.object(gemini_client, "_post_gemini", _no_network)
        cls._net_patch.start()
        cls.client = TestClient(main.app)

    @classmethod
    def tearDownClass(cls):
        cls._net_patch.stop()

    def _post(self, request: dict, *gemini_responses: str):
        queue = list(gemini_responses)
        prompts: list = []

        async def _stub(*, prompt: str) -> str:
            prompts.append(prompt)
            return queue.pop(0)

        with mock.patch.object(route, "call_gemini_for_liquidation_plan", _stub):
            r = self.client.post("/ai/generate-liquidation-plan", json=request,
                                 headers={"X-LTC-Device-ID": f"a2-{uuid.uuid4()}"})
        return r, prompts


class PlanRequestCompatibilityTests(_PlanRouteTestCase):

    def test_v1_request_still_works(self):
        r, prompts = self._post(V1_REQUEST, _plan_json([_step("Shortlist camera consignors")]))
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["items"][0]["text"], "Shortlist camera consignors")
        # The chosen option is found in the Brief even without selectedOption.
        self.assertIn("Specialist camera consignment", prompts[0])

    def test_v2_full_context_reaches_the_prompt(self):
        p = _prompt(_v2())
        for expected in ("Leica M3 rangefinder with 50mm Summicron lens", "Photos already saved in LTC: 8",
                         "Supporting documents already saved: 1 (Receipt)", "audio story",
                         "1,400 USD to 2,200 USD", "Based on recent sales of M3 bodies",
                         "Specific recommendation: Specialist camera consignment",
                         "1,100 USD to 1,500 USD", "Commission of 20 to 30 percent",
                         "Most specialists accept insured mail-in", "Time: 3 to 8 weeks",
                         "Whether the shutter fires accurately", "Lens glass is clear"):
            self.assertIn(expected, p)
        self.assertNotIn("Local fallback used", p)  # describes the Brief, not the item

    def test_a1_specialty_reaches_the_prompt(self):
        p = _prompt(_v2())
        for expected in ("Kind of item: film camera", "Brand or maker: Leica", "Model: M3",
                         "Identifying details: rangefinder, 50mm lens",
                         "Specialist dealers or consignors exist"):
            self.assertIn(expected, p)

    def test_partial_v2_context_is_accepted(self):
        req = copy.deepcopy(V1_REQUEST)
        req["selectedOption"] = CAMERA_BRIEF["pathOptions"][1]
        r, prompts = self._post(req, _plan_json([_step("Shortlist camera consignors")]))
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIn("Specific recommendation: Specialist camera consignment", prompts[0])

    def test_prompt_never_shows_internal_identifiers(self):
        for req in (V1_REQUEST, _v2(), _v2(chosenPath="donate", isRecommended=False), CLOSET_SET_REQUEST):
            p = _prompt(req)
            for raw in RAW_IDS:
                self.assertNotIn(raw, p, f"{raw} in prompt for {req['chosenPath']}")


class StrategyTests(_PlanRouteTestCase):

    def test_chosen_option_not_recommendation_controls_strategy(self):
        p = _prompt(_v2(chosenPath="pathC_quickExit", selectedOption=CAMERA_BRIEF["pathOptions"][2],
                        isRecommended=False))
        self.assertIn("The owner chose Quick Sale. The Brief recommended Consignment", p)
        self.assertIn("plan ONLY for Quick Sale and do not steer back to Consignment", p)
        self.assertIn("Specific recommendation: Sell to a local camera shop", p)
        self.assertNotIn("Specialist camera consignment", p)
        self.assertIn("What a good Quick Sale plan covers", p)

    def test_mismatched_selected_option_is_ignored(self):
        # selectedOption for another path never overrides the chosen approach.
        p = _prompt(_v2(chosenPath="pathA_maximizePrice", selectedOption=CAMERA_BRIEF["pathOptions"][1]))
        self.assertIn("Specific recommendation: Sell online yourself", p)

    def test_each_approach_has_its_own_guidance(self):
        bodies = {path: _prompt(_v2(chosenPath=path, isRecommended=False))
                  for path in ("pathA_maximizePrice", "pathB_delegateConsign", "pathC_quickExit", "donate")}
        self.assertIn("confirming they will accept it before handing it over", bodies["pathB_delegateConsign"])
        self.assertIn("transaction safety", bodies["pathC_quickExit"])
        self.assertIn("getting a receipt", bodies["donate"])
        self.assertIn("how to judge offers", bodies["pathA_maximizePrice"])

    def test_needs_info_brief_does_not_block_a_chosen_approach(self):
        brief = {**CAMERA_BRIEF, "recommendedPath": "needsInfo",
                 "missingDetails": ["Maker and model"], "specialty": None}
        req = _v2(brief=brief, isRecommended=False, selectedOption=None, itemContext=None)
        r, prompts = self._post(req, _plan_json([_step("Find the maker's mark")]))
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIn("PROVISIONAL PLAN", prompts[0])
        self.assertIn("Maker and model", prompts[0])
        self.assertIn("The owner chose Consignment", prompts[0])

    def test_rules_are_category_independent(self):
        sewing = _v2(category="Uncategorized", title="Singer Featherweight 221 sewing machine",
                     brief={**CAMERA_BRIEF, "specialty": None}, selectedOption=None,
                     itemContext={"description": "Black Singer 221 with case.", "photoCount": 3})
        p = _prompt(sewing)
        self.assertIn("Singer Featherweight 221 sewing machine", p)
        self.assertIn("Black Singer 221 with case.", p)
        self.assertIn("Draw on the item's own description and kind", p)
        self.assertNotIn("CLOSET LOT", p)
        # The fixed instructions (strategy guidance and step rules) name no item category.
        fixed = (p.split("What a good Consignment plan covers:")[1].split("THE CHOSEN OPTION")[0]
                 + p.split("STEP RULES:")[1]).lower()
        for word in ("camera", "furniture", "handbag", "jewelry", "clothing", "sewing", "china"):
            self.assertNotIn(word, fixed)


class ClosetLotTests(_PlanRouteTestCase):

    def test_closet_lot_set_gets_pile_rules_and_groups(self):
        p = _prompt(CLOSET_SET_REQUEST)
        self.assertIn("CLOSET LOT (a clothing set)", p)
        self.assertIn('"group": "luxury"', p)
        self.assertIn("Brands: Chanel, J.Crew, Talbots", p)
        # App 1.2 sends category "Clothing" for closet lots in some flows.
        self.assertIn("CLOSET LOT", _prompt({**CLOSET_SET_REQUEST, "category": "Clothing", "setContext": None}))

    def test_single_clothing_item_is_not_a_closet_lot(self):
        p = _prompt(_v2(category="Clothing", title="Burberry trench coat"))
        self.assertNotIn("CLOSET LOT", p)
        self.assertNotIn('"group"', p)

    def test_other_sets_get_set_rules(self):
        china = {**CLOSET_SET_REQUEST, "category": "China/Dinnerware", "title": "Noritake china",
                 "setContext": {**CLOSET_SET_REQUEST["setContext"], "setType": "China/Dinnerware", "story": None,
                                "memberSummaries": [{"title": "Dinner plate", "category": "China & Crystal",
                                                     "quantity": 12, "unitValue": 15}]}}
        p = _prompt(china)
        self.assertIn("SET:", p)
        self.assertNotIn("CLOSET LOT", p)
        self.assertIn("Dinner plate | China & Crystal | qty 12", p)

    def test_set_member_photo_counts_reach_the_prompt(self):
        members = [{"title": "Dinner plate", "category": "China & Crystal", "quantity": 12, "unitValue": 15,
                    "photoCount": 3},
                   {"title": "Platter", "category": "China & Crystal", "quantity": 1, "unitValue": 40,
                    "photoCount": 2},
                   {"title": "Gravy boat", "category": "China & Crystal", "quantity": 1}]  # app 1.2 shape
        china = {**CLOSET_SET_REQUEST, "category": "China/Dinnerware", "title": "Noritake china",
                 "setContext": {**CLOSET_SET_REQUEST["setContext"], "setType": "China/Dinnerware",
                                "story": None, "memberSummaries": members}}
        p = _prompt(china)
        self.assertIn("Dinner plate | China & Crystal | qty 12 | value each 15 USD | photos saved: 3", p)
        self.assertIn("Gravy boat | China & Crystal | qty 1 | value each not estimated\n", p)
        self.assertIn("Photos already saved across listed members: 5", p)

    def test_groups_kept_for_closet_lot_and_dropped_elsewhere(self):
        items = [_step("Split the lot into piles", group="other"),
                 _step("Ship designer pieces to a luxury consignor", group="luxury"),
                 _step("Bag everyday pieces for donation", group="charity")]
        r, _ = self._post(CLOSET_SET_REQUEST, _plan_json(items))
        self.assertEqual([s["group"] for s in r.json()["items"]], ["other", "luxury", None])

        r, _ = self._post(V1_REQUEST, _plan_json(items))
        self.assertEqual([s["group"] for s in r.json()["items"]], [None, None, None])


class ChecklistCleanupTests(_PlanRouteTestCase):

    def test_identifiers_and_partner_codes_are_removed(self):
        items = [
            _step("Use the pathB_delegateConsign route (partnerType: luxury_hub_mailin) for designer pieces",
                  detail="Path B is the hub-first flow."),
            _step("Send the luxury pile to a luxury_hub_mailin partner"),
        ]
        r, _ = self._post(CLOSET_SET_REQUEST, _plan_json(items, focus="Follow pathB_delegateConsign."))
        body = r.json()
        visible = [body["focus"]] + [s["text"] for s in body["items"]] + [s["detail"] or "" for s in body["items"]]
        for text in visible:
            for raw in RAW_IDS:
                self.assertNotIn(raw, text)
        self.assertEqual(body["items"][0]["text"], "Use the Consignment route for designer pieces")
        self.assertEqual(body["items"][1]["text"], "Send the luxury pile to a luxury mail-in consignment partner")
        self.assertEqual(body["focus"], "Follow Consignment.")

    def test_repeated_steps_are_removed_but_similar_distinct_steps_kept(self):
        items = [
            _step("Ask two camera specialists for consignment terms"),
            _step("Ask two camera specialists for consignment terms."),        # exact repeat
            _step("ask two camera specialists for their consignment terms"),  # near-identical
            _step("Ship the camera insured to the consignor you choose"),
            _step("Ship the lens insured to the consignor you choose"),       # different object: keep
        ]
        r, _ = self._post(_v2(), _plan_json(items))
        texts = [s["text"] for s in r.json()["items"]]
        self.assertEqual(texts, [
            "Ask two camera specialists for consignment terms",
            "Ship the camera insured to the consignor you choose",
            "Ship the lens insured to the consignor you choose",
        ])
        self.assertEqual([s["order"] for s in r.json()["items"]], [1, 2, 3])

    def test_meaningful_category_specific_steps_survive(self):
        items = [
            _step("Fire the shutter at 1/1000 and 1 second and listen for sticking",
                  detail="Specialists price M3 bodies on shutter accuracy."),
            _step("Photograph the serial number on the top plate", action="findSpecialtyHelp"),
        ]
        r, _ = self._post(_v2(), _plan_json(items))
        body = r.json()["items"]
        self.assertEqual(body[0]["text"], items[0]["text"])
        self.assertEqual(body[0]["detail"], items[0]["detail"])
        self.assertEqual(body[1]["action"], "findSpecialtyHelp")

    def test_optional_fields_missing_or_invalid_are_safe(self):
        items = ["Shortlist camera consignors",
                 _step("Compare commission and payout timing", detail=None, action="callThem", group=7),
                 {"step": "Keep the signed agreement", "isCompleted": True}]
        r, _ = self._post(_v2(), _plan_json(items))
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertIsNone(body["focus"])
        self.assertEqual([s["text"] for s in body["items"]],
                         ["Shortlist camera consignors", "Compare commission and payout timing",
                          "Keep the signed agreement"])
        self.assertTrue(all(s["action"] is None and s["group"] is None and s["detail"] is None
                            for s in body["items"]))
        self.assertFalse(any(s["isCompleted"] for s in body["items"]))  # new Plans start unchecked

    def test_runaway_output_is_bounded(self):
        items = [_step(f"Distinct step number {i} about item part {i * 7}") for i in range(20)]
        r, _ = self._post(_v2(), _plan_json(items))
        self.assertEqual(len(r.json()["items"]), route._PLAN_MAX_STEPS)

    def test_provenance_is_stamped(self):
        r, _ = self._post(_v2(), _plan_json([_step("Shortlist camera consignors")]))
        self.assertEqual(r.json()["aiProvider"], "gemini")
        self.assertTrue(r.json()["aiModel"])


class ControlledFailureTests(_PlanRouteTestCase):

    def test_empty_plan_is_repaired(self):
        r, prompts = self._post(_v2(), _plan_json([]), _plan_json([_step("Shortlist camera consignors")]))
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(len(prompts), 2)
        self.assertIn("DID NOT validate", prompts[1])

    def test_unrepairable_output_is_a_controlled_502(self):
        r, prompts = self._post(_v2(), "not json at all", _plan_json([{"text": "   "}]))
        self.assertEqual(r.status_code, 502)
        self.assertEqual(len(prompts), 2)
        self.assertNotIn("items", r.json())  # no half-formed Plan is returned


if __name__ == "__main__":
    unittest.main()
