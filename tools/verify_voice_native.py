#!/usr/bin/env python3
"""Exercise the real native engine with a caller-supplied local test WAV.
Never records a microphone, calls a speech API, or prints the transcript.
"""
import argparse, ctypes, hashlib, pathlib, tempfile, time, wave

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--library',required=True);parser.add_argument('--model',required=True)
    parser.add_argument('--audio',required=True);parser.add_argument('--expect-word')
    args=parser.parse_args()
    with open(args.model,'rb') as f:
        digest=hashlib.sha256()
        for chunk in iter(lambda:f.read(1024*1024),b''): digest.update(chunk)
    if digest.hexdigest()!='422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898': raise SystemExit('Modelo no verificado')
    lib=ctypes.CDLL(str(pathlib.Path(args.library).resolve()))
    lib.conecta_voice_transcribe.argtypes=[ctypes.c_int32,ctypes.c_char_p,ctypes.c_char_p,ctypes.POINTER(ctypes.c_char_p)]
    lib.conecta_voice_free.argtypes=[ctypes.c_void_p]
    def transcribe(token,audio):
        output=ctypes.c_char_p()
        try:
            code=lib.conecta_voice_transcribe(token,args.model.encode(),str(audio).encode(),ctypes.byref(output))
            return code,output.value.decode() if output.value else ''
        finally:
            if output: lib.conecta_voice_free(ctypes.cast(output,ctypes.c_void_p))
    start=time.monotonic();code,text=transcribe(lib.conecta_voice_begin(),args.audio)
    assert code==0 and text.strip(),'Transcripción vacía o fallida'
    if args.expect_word: assert args.expect_word.lower() in text.lower(),'No se reconoció la palabra esperada'
    print(f'Transcripción local: PASS ({time.monotonic()-start:.2f} s; no es una medición en teléfonos)')
    token=lib.conecta_voice_begin();assert lib.conecta_voice_begin()==-1
    lib.conecta_voice_cancel(token);assert transcribe(token,args.audio)[0]==-2
    with tempfile.TemporaryDirectory(prefix='conecta2-native-test-') as temp:
        silent=pathlib.Path(temp)/'silent.wav'
        with wave.open(str(silent),'wb') as wav:
            wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(16000);wav.writeframes(bytes(32000))
        assert transcribe(lib.conecta_voice_begin(),silent)==(0,'')
        invalid=pathlib.Path(temp)/'invalid.wav';invalid.write_bytes(b'invalid')
        assert transcribe(lib.conecta_voice_begin(),invalid)[0]==-3
    print('Concurrencia, cancelación, silencio y WAV inválido: PASS')

if __name__=='__main__':main()
