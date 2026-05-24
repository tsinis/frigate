# Visual Regression Golden Images

This directory houses the reference visual golden regression assets (`*.png`) for standard and composite shapes (Rectangle, Oval, Text, Polygon) in `frigatebird/rust`.

## Regenerating Goldens

If you introduce visual changes or add new shapes and need to regenerate the reference `.png` images, perform the following:

1. Delete the existing `.png` golden file(s) that you wish to regenerate from this directory.
2. Run the cargo test suite:

   ```bash
   rustup run nightly-2026-05-02 cargo test --workspace
   ```

3. The test suite automatically detects that the golden files are missing, draws the new shapes onto a blank paint canvas, saves them as the new reference images, and panics with:
   > _"Golden did not exist; wrote new golden to ... Inspect visually, commit it, then re-run."_
4. Inspect the generated images in `tests/golden/` visually.
5. Re-run `rustup run nightly-2026-05-02 cargo test --workspace` to confirm that the tests now pass cleanly with the newly generated golden baselines.
