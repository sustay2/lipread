import cv2
import numpy as np

class FramePreprocessor:
    def __init__(self, crop_size=96):
        self.crop_size = crop_size
        # LRS3 Statistics (Mean & Std Dev for normalization)
        self.mean = 0.421
        self.std = 0.165

    def align_and_crop(self, frame, landmarks):
        # 1. Identify key landmarks (MediaPipe indices)
        h, w = frame.shape[:2]
        p_left_eye = np.array([landmarks[33].x * w, landmarks[33].y * h])
        p_right_eye = np.array([landmarks[263].x * w, landmarks[263].y * h])
        p_upper_lip = np.array([landmarks[13].x * w, landmarks[13].y * h])
        p_lower_lip = np.array([landmarks[14].x * w, landmarks[14].y * h])
        
        # 2. Calculate Angle to rotate
        delta = p_right_eye - p_left_eye
        angle = np.degrees(np.arctan2(delta[1], delta[0]))
        
        # 3. Calculate Mouth Center
        mouth_center = (p_upper_lip + p_lower_lip) / 2.0
        
        # 4. Create Rotation Matrix
        M = cv2.getRotationMatrix2D(tuple(mouth_center), angle, 1.0)
        
        # 5. Warp (Rotate) the entire image
        rotated_img = cv2.warpAffine(frame, M, (w, h))
        
        # 6. Crop the mouth from the ROTATED image
        cx, cy = int(mouth_center[0]), int(mouth_center[1])
        half_s = self.crop_size // 2
        
        # Boundary checks
        y1, y2 = max(0, cy - half_s), min(h, cy + half_s)
        x1, x2 = max(0, cx - half_s), min(w, cx + half_s)
        
        crop = rotated_img[y1:y2, x1:x2]
        
        # Handle edge cases where crop is smaller than 96x96 (e.g. face at edge of screen)
        if crop.shape[0] != self.crop_size or crop.shape[1] != self.crop_size:
            crop = cv2.resize(crop, (self.crop_size, self.crop_size))

        return crop

    def to_model_input(self, gray_crop):
        # Normalize: (Pixel - Mean) / Std
        normalized = (gray_crop.astype(np.float32) / 255.0 - self.mean) / self.std
        return normalized
    
class StreamBuffer:
    def __init__(self, window_size=50, stride=25):
        self.buffer = []
        self.window_size = window_size # 50 frames (2 seconds)
        self.stride = stride           # 25 frames overlap
    
    def add_frame(self, frame):
        self.buffer.append(frame)
    
    def is_ready(self):
        return len(self.buffer) >= self.window_size
    
    def get_batch(self):
        # Return the batch for inference
        # Shape: (1, 1, 50, 96, 96)
        batch = np.array(self.buffer[:self.window_size])
        
        self.buffer = self.buffer[self.stride:]
        
        return batch[np.newaxis, np.newaxis, ...]