import { useEntitySheet } from "~/context/entity-sheet";
import { InferencePreviewSheet } from "~/components/inference/InferencePreviewSheet";
import { EpisodePreviewSheet } from "~/components/episode/EpisodePreviewSheet";
import { ModelInferencePreviewSheet } from "~/components/model-inference/ModelInferencePreviewSheet";

export function EntitySheet() {
  const { sheetState, closeSheet } = useEntitySheet();

  if (!sheetState) return null;

  switch (sheetState.type) {
    case "inference":
      return (
        <InferencePreviewSheet
          inferenceId={sheetState.id}
          isOpen
          onClose={closeSheet}
        />
      );
    case "episode":
      return (
        <EpisodePreviewSheet
          episodeId={sheetState.id}
          isOpen
          onClose={closeSheet}
        />
      );
    case "model_inference":
      return (
        <ModelInferencePreviewSheet
          modelInferenceId={sheetState.id}
          isOpen
          onClose={closeSheet}
        />
      );
    default: {
      const _exhaustiveCheck: never = sheetState;
      return _exhaustiveCheck;
    }
  }
}
