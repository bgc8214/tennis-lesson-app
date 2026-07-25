"use client";

/**
 * 온디바이스 STT(iOS 26 SpeechAnalyzer) 실험용 진단 페이지.
 *
 * 실측 결과(2026-07-25, 골든셋 대조): 소음 많은 한국어 테니스 코칭 도메인에서
 * 정확도가 낮다(29건 중 2건 매칭). 프로덕션 파이프라인이 아니라 "실기기에서
 * 직접 돌려보기" 용도의 실험 페이지 — 반드시 iOS 26+ 실기기(Capacitor 앱)에서
 * 열어야 동작한다. 웹/시뮬레이터에서는 OnDeviceSTT 플러그인이 없다.
 */

import { useCallback, useState } from "react";
import { extractAudioFromVideo } from "@/lib/extractAudio";
import { OnDeviceSTT, type OnDeviceSttResult } from "@/lib/onDeviceStt";

type Phase = "idle" | "extracting" | "writing" | "transcribing" | "done" | "error";

function uint8ToBase64(data: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < data.length; i += chunkSize) {
    const chunk = data.subarray(i, i + chunkSize);
    binary += String.fromCharCode(...chunk);
  }
  return btoa(binary);
}

export default function OnDeviceSttTestPage() {
  const [phase, setPhase] = useState<Phase>("idle");
  const [message, setMessage] = useState("");
  const [elapsedMs, setElapsedMs] = useState<number | null>(null);
  const [result, setResult] = useState<OnDeviceSttResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleFile = useCallback(async (file: File) => {
    setResult(null);
    setError(null);
    setElapsedMs(null);

    try {
      const availability = await OnDeviceSTT.isAvailable();
      if (!availability.available) {
        throw new Error(availability.reason ?? "이 기기에서 온디바이스 STT를 쓸 수 없습니다");
      }

      let audioBytes: Uint8Array;
      const isAudio = file.type.startsWith("audio/") || /\.(wav|m4a|mp3|aac)$/i.test(file.name);

      if (isAudio) {
        audioBytes = new Uint8Array(await file.arrayBuffer());
      } else {
        setPhase("extracting");
        setMessage("영상에서 오디오 추출 중...");
        const extracted = await extractAudioFromVideo(file, (p) => setMessage(p.message));
        audioBytes = extracted.data;
      }

      setPhase("writing");
      setMessage("네이티브 파일시스템에 쓰는 중...");
      const { Filesystem, Directory } = await import("@capacitor/filesystem");
      const base64 = uint8ToBase64(audioBytes);
      const fileName = `ondevice-stt-test-${Date.now()}.m4a`;
      const written = await Filesystem.writeFile({
        path: fileName,
        data: base64,
        directory: Directory.Cache,
      });

      setPhase("transcribing");
      setMessage("SpeechAnalyzer로 전사 중... (모델 첫 다운로드 시 시간이 걸릴 수 있음)");
      const t0 = performance.now();
      const sttResult = await OnDeviceSTT.transcribe({ path: written.uri, language: "ko-KR" });
      setElapsedMs(performance.now() - t0);

      setResult(sttResult);
      setPhase("done");
    } catch (e) {
      setPhase("error");
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  return (
    <div style={{ padding: 24, fontFamily: "sans-serif", maxWidth: 720, margin: "0 auto" }}>
      <h1 style={{ fontSize: 20, fontWeight: 700 }}>온디바이스 STT 실험 (SpeechAnalyzer)</h1>
      <p style={{ color: "#666", fontSize: 14, marginTop: 8 }}>
        iOS 26+ 실기기(Capacitor 앱)에서만 동작합니다. 영상 또는 오디오 파일을 선택하세요.
      </p>

      <input
        type="file"
        accept="video/*,audio/*"
        style={{ marginTop: 16 }}
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) handleFile(file);
        }}
      />

      {phase !== "idle" && phase !== "done" && phase !== "error" && (
        <p style={{ marginTop: 16, color: "#333" }}>[{phase}] {message}</p>
      )}

      {error && (
        <p style={{ marginTop: 16, color: "#c00", whiteSpace: "pre-wrap" }}>에러: {error}</p>
      )}

      {result && (
        <div style={{ marginTop: 24 }}>
          <p>
            locale: {result.locale} · 세그먼트 {result.segments.length}개
            {elapsedMs != null && ` · 처리 시간 ${(elapsedMs / 1000).toFixed(1)}s`}
          </p>
          <div style={{ marginTop: 12, display: "flex", flexDirection: "column", gap: 8 }}>
            {result.segments.map((s, i) => (
              <div key={i} style={{ borderBottom: "1px solid #eee", paddingBottom: 8 }}>
                <div style={{ fontSize: 12, color: "#888" }}>
                  {Math.round(s.startSec)}s ~ {Math.round(s.endSec)}s
                </div>
                <div>{s.text}</div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
