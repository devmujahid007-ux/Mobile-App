/// BraTS-style modality keys expected by `POST /mri/upload` and `POST /predict`.
const mriModalityKeys = ['t1c', 't1n', 't2f', 't2w'];

const mriModalityLabels = {
  't1c': 'T1C',
  't1n': 'T1N',
  't2f': 'T2F',
  't2w': 'T2W',
};
