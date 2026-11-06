import math
import torch
from torch.nn import functional as F


def distillation_loss(student, teacher, labels, temperature, alpha):
    if not math.isfinite(temperature) or temperature <= 0 or not math.isfinite(alpha) or not 0 <= alpha <= 1:
        raise ValueError('positive temperature and mixture in 0..1 required')
    if student.ndim != 2 or student.shape != teacher.shape or student.shape[0] == 0 or student.shape[1] < 2:
        raise ValueError('aligned nonempty multiclass logits required')
    if labels.shape != student.shape[:1] or labels.dtype != torch.long:
        raise ValueError('one integer target per observation required')
    if not bool(torch.isfinite(student).all()) or not bool(torch.isfinite(teacher).all()):
        raise ValueError('finite logits required')
    hard = F.cross_entropy(student, labels)
    target = F.softmax(teacher.detach() / temperature, dim=-1)
    soft = F.kl_div(F.log_softmax(student / temperature, dim=-1), target, reduction='batchmean')
    return (1 - alpha) * hard + alpha * temperature ** 2 * soft
