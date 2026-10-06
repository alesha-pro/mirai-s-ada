@echo off
rem Build the engine (engine\ = llama.cpp-ada-mirai, branch main) into build\ with Ninja and the pip CUDA 13
rem toolkit, sm_89 machine code only (this card). Usage: tooling\build_engine.bat llama-server [more targets]
rem Then tooling\install_bin.ps1 copies the result into bin\ (the CUDA runtime DLLs already live there).
setlocal
set ROOT=%~dp0..
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set CUDA_PATH=C:\Users\pwall\AppData\Local\Programs\Python\Python312\Lib\site-packages\nvidia\cu13
set CUDAToolkit_ROOT=%CUDA_PATH%
set PATH=%ROOT%\tooling\ninja;%CUDA_PATH%\bin;%CUDA_PATH%\bin\x86_64;%CUDA_PATH%\nvvm\bin;%PATH%
set SRC=%ROOT%\engine
set BUILD=%ROOT%\build
set CMAKE="C:\Users\pwall\AppData\Local\Programs\Python\Python312\Scripts\cmake.exe"
if not exist "%BUILD%\build.ninja" (
  %CMAKE% -S "%SRC%" -B "%BUILD%" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_MAKE_PROGRAM=%ROOT%\tooling\ninja\ninja.exe -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89-real -DGGML_CUDA_GRAPHS=ON -DLLAMA_BUILD_SERVER=ON -DLLAMA_BUILD_TESTS=ON -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_CURL=OFF -DGGML_RPC=OFF -DGGML_BLAS=OFF -DGGML_NATIVE=OFF -DGGML_CCACHE=OFF -DCMAKE_CUDA_COMPILER="%CUDA_PATH%\bin\nvcc.exe" -DCUDAToolkit_ROOT="%CUDA_PATH%"
  if errorlevel 1 exit /b 1
)
%CMAKE% --build "%BUILD%" --target %* -j 6
