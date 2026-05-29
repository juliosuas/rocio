from playwright.sync_api import sync_playwright

URL = "http://127.0.0.1:8765/?reset=1&v=local-test"

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 390, "height": 844}, is_mobile=True)
    errors = []
    failed = []
    page.on("pageerror", lambda exc: errors.append(str(exc)))
    page.on("requestfailed", lambda request: failed.append(request.url))
    page.goto(URL)
    page.wait_for_load_state("networkidle")
    page.wait_for_function("typeof LOCAL_FLOWER_REFERENCE_DESCRIPTORS !== 'undefined'")
    page.evaluate("() => localFlowerReferencePromise")
    page.wait_for_function("LOCAL_FLOWER_REFERENCE_DESCRIPTORS && LOCAL_FLOWER_REFERENCE_DESCRIPTORS.length === 15")

    catalog = page.evaluate(
        """
        async () => {
          const rows = [];
          for (const flower of FLOWERS) {
            const canvas = await loadImageAsCanvas(flower.img);
            const result = identifyPlant(canvas);
            rows.push({
              expected: flower.id,
              actual: result.flowerId,
              confidence: result.confidence,
              uncertain: result.isUncertain,
              noClearFlower: !!result.noClearFlower,
              candidates: (result.candidates || []).map(c => c.flowerId)
            });
          }
          return rows;
        }
        """
    )

    leaf_case = page.evaluate(
        """
        () => {
          const canvas = document.createElement('canvas');
          canvas.width = 720;
          canvas.height = 960;
          const ctx = canvas.getContext('2d');
          const grad = ctx.createLinearGradient(0, 0, canvas.width, canvas.height);
          grad.addColorStop(0, '#6b4a2c');
          grad.addColorStop(0.55, '#8a6136');
          grad.addColorStop(1, '#3f2b1d');
          ctx.fillStyle = grad;
          ctx.fillRect(0, 0, canvas.width, canvas.height);
          for (const [x, y, r] of [[170, 260, 95], [390, 350, 120], [620, 240, 115]]) {
            ctx.save();
            ctx.translate(x, y);
            ctx.scale(1.15, 0.72);
            ctx.beginPath();
            ctx.arc(0, 0, r, 0, Math.PI * 2);
            ctx.fillStyle = '#93d447';
            ctx.fill();
            ctx.restore();
            ctx.fillStyle = '#5e8b32';
            ctx.fillRect(x - 7, y, 14, 260);
          }
          const result = identifyPlant(canvas);
          return {
            actual: result.flowerId,
            confidence: result.confidence,
            uncertain: result.isUncertain,
            noClearFlower: !!result.noClearFlower,
            candidates: (result.candidates || []).map(c => c.flowerId)
          };
        }
        """
    )

    print({"catalog": catalog, "leafCase": leaf_case, "errors": errors, "failedRequests": failed})
    browser.close()

    bad_catalog = [row for row in catalog if row["actual"] != row["expected"] or row["noClearFlower"]]
    if bad_catalog:
        raise SystemExit(f"Catalog regression failed: {bad_catalog}")
    if not leaf_case["noClearFlower"] or leaf_case["actual"] == "lirio":
        raise SystemExit(f"Leaf/background case should not be lirio: {leaf_case}")
    if errors or failed:
        raise SystemExit(f"Browser errors={errors} failed={failed}")
