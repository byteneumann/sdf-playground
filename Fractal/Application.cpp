#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <d3dcompiler.h>

#include "Application.h"
#include "Math3D.h"
#include "Util.h"

#pragma comment(lib, "d3dcompiler.lib")

using namespace Math3D;


bool Application::Init(HINSTANCE hInstance)
{
	WNDCLASS wc = { 0 };
	wc.cbWndExtra = sizeof(this);
	wc.hCursor = LoadCursor(0, IDC_ARROW);
	wc.hInstance = hInstance;
	wc.lpszClassName = "Mainwnd";
	wc.lpfnWndProc = sWndProc;

	RegisterClass(&wc);

	bool fullscreen = true;
	std::string title = "SDF Fractal";

	if (fullscreen)
	{
		unsigned width = GetSystemMetrics(SM_CXSCREEN);
		unsigned height = GetSystemMetrics(SM_CXSCREEN);
		hWnd = CreateWindow(wc.lpszClassName, title.c_str(), WS_POPUP, 0, 0, width, height, 0, 0, hInstance, this);
	}
	else
	{
		unsigned windowstyle = WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
		int xpos = CW_USEDEFAULT;
		int ypos = CW_USEDEFAULT;
		unsigned width = 800;
		unsigned height = 600;

		RECT r;
		SetRect(&r, 0, 0, width, height);
		AdjustWindowRect(&r, windowstyle, 0);
		hWnd = CreateWindow(wc.lpszClassName, title.c_str(), windowstyle, xpos, ypos, r.right - r.left, r.bottom - r.top, 0, 0, hInstance, this);
	}

	if (!hWnd)
	{
		return false;
	}

	mouse_tracking = false;
	for (auto &elem : keystate)
	{
		elem = false;
	}

	return initGraphics();
}


void Application::Run()
{
	ShowWindow(hWnd, SW_SHOWNORMAL);

	DWORD lasttime = GetTickCount();

	MSG Msg;
	do
	{
		while (PeekMessage(&Msg, 0, 0, 0, PM_REMOVE))
		{
			TranslateMessage(&Msg);
			DispatchMessage(&Msg);
		}

		unsigned newtime = GetTickCount();
		unsigned diff = newtime - lasttime;
		lasttime = newtime;

		updateSimulation(static_cast<float>(diff) / 1000.f);
		render();
	}
	while (Msg.message != WM_QUIT);
}


LRESULT CALLBACK Application::sWndProc(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam)
{
	if (Msg == WM_NCCREATE)
	{
		SetWindowLongPtr(hWnd, 0, reinterpret_cast<LONG_PTR>(reinterpret_cast<CREATESTRUCT *>(lParam)->lpCreateParams));
	}
	Application *app = reinterpret_cast<Application *>(GetWindowLongPtr(hWnd, 0));
	if (app)
	{
		return app->WndProc(hWnd, Msg, wParam, lParam);
	}
	return DefWindowProc(hWnd, Msg, wParam, lParam);
}


LRESULT CALLBACK Application::WndProc(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam)
{
	switch (Msg)
	{
	case WM_MOUSEMOVE:
		{
			if (mouse_tracking)
			{
				int xdiff = LOWORD(lParam) - lastmouse.x;
				int ydiff = HIWORD(lParam) - lastmouse.y;
				if (xdiff || ydiff)
				{
					camera.RotateY(xdiff / -500.f);
					camera.RotateX(ydiff / -500.f);
				}
			}
			lastmouse.x = LOWORD(lParam);
			lastmouse.y = HIWORD(lParam);
		}
		break;
	case WM_KEYDOWN:
		keystate[static_cast<char>(LOWORD(wParam))] = true;
		if (LOWORD(wParam) == VK_ESCAPE)
		{
			PostQuitMessage(0);
		}
		break;
	case WM_KEYUP:
		keystate[static_cast<char>(LOWORD(wParam))] = false;
		break;
	case WM_LBUTTONDOWN:
		mouse_tracking = true;
		break;
	case WM_LBUTTONUP:
		mouse_tracking = false;
		break;
	case WM_DESTROY:
		PostQuitMessage(0);
		break;
	}
	return DefWindowProc(hWnd, Msg, wParam, lParam);
}


bool Application::initGraphics()
{
	graphics = std::make_unique<Graphics>();
	if (!graphics->init(hWnd))
		return false;

	if (!initShaders())
		return false;

	if (!initGeometry())
		return false;

	RECT rect;
	GetClientRect(hWnd, &rect);
	float width = static_cast<float>(rect.right - rect.left);
	float height = static_cast<float>(rect.bottom - rect.top);

	camera.SetCameraMode(Camera::CameraModeFPS);
	camera.SetAspect(width / height);
	camera.SetFOVY(ToRadian(60));
	camera.SetNearPlane(1.f);
	camera.SetFarPlane(300.f);
	camera.SetMinXAngle(ToRadian(80.f));
	camera.SetMaxXAngle(ToRadian(80.f));
	camera.SetRoll(0.f);
	
	camera.SetEye(Vector3(3.f, 2.f, -6.f));
	camera.SetLookat(Vector3(0.f, 0.f, 0.f));

	stime = 0.f;

	return true;
}


Comptr<ID3DBlob> Application::compileShader(const std::string &filename, const std::string &profile, const std::string &entry, bool display_warnings, bool disassemble)
{
	// first load the file
	std::ifstream file(filename);
	if (!file)
	{
		ErrorBox(Format() << "Could not load file \"" << filename << "\"");
	}
	std::string code = readFromFile(file);

	// then try to compile it
	UINT flags =
#ifdef _DEBUG
		D3DCOMPILE_DEBUG |
#endif
		0;

	Comptr<ID3DBlob> compiled, error;
	D3DCompile(code.c_str(), code.length(), filename.c_str(), nullptr, D3D_COMPILE_STANDARD_FILE_INCLUDE, entry.c_str(), profile.c_str(), flags, 0, &compiled, &error);
	if (error)
	{
		if (!compiled) // no code, thus an error
		{
			ErrorBox(static_cast<const char *>(error->GetBufferPointer()));
		}
		else if (display_warnings) // its a warning, since we got the code
		{
			WarningBox(static_cast<const char *>(error->GetBufferPointer()));
		}
	}

	if (disassemble && compiled)
	{
		UINT disasm_flags = 0;
		Comptr<ID3DBlob> disassembled;
		D3DDisassemble(compiled->GetBufferPointer(), compiled->GetBufferSize(), disasm_flags, nullptr, &disassembled);
		if (disassembled)
		{
			std::string output_filename = changeFileExtension(filename, "asm");
			std::ofstream out_file(output_filename, std::ios::out);
			out_file.write(static_cast<const char *>(disassembled->GetBufferPointer()), disassembled->GetBufferSize() - 1);
		}
	}

	return compiled;
}


bool Application::initShaders()
{
	UINT flags =
#ifdef _DEBUG
		D3DCOMPILE_DEBUG |
#endif
		0;

	Comptr<ID3DBlob> v_compiled = compileShader("shader/vshader.hlsl", "vs_5_0", "vs_main");
	if (!v_compiled)
		return false;

	Comptr<ID3DBlob> p_compiled = compileShader("shader/pshader.hlsl", "ps_5_0", "ps_main");
	if (!p_compiled)
		return false;

	auto device = graphics->GetDevice();
	HRESULT hr = device->CreateVertexShader(v_compiled->GetBufferPointer(), v_compiled->GetBufferSize(), 0, &v_shader);
	if (FAILED(hr))
		return false;

	hr = device->CreatePixelShader(p_compiled->GetBufferPointer(), p_compiled->GetBufferSize(), 0, &p_shader);
	if (FAILED(hr))
		return false;
	
	auto context = graphics->GetContext();
	context->VSSetShader(v_shader, nullptr, 0);
	context->PSSetShader(p_shader, nullptr, 0);

	// build the input assembler
	D3D11_INPUT_ELEMENT_DESC input_desc[] =
	{
		{"POSITION", 0, DXGI_FORMAT_R32G32_FLOAT, 0, D3D11_APPEND_ALIGNED_ELEMENT, D3D11_INPUT_PER_VERTEX_DATA, 0},
	};

	hr = device->CreateInputLayout(input_desc, static_cast<UINT>(std::size(input_desc)), v_compiled->GetBufferPointer(), v_compiled->GetBufferSize(), &input_layout);
	if (FAILED(hr))
		return false;

	context->IASetInputLayout(input_layout);

	return true;
}


bool Application::initGeometry()
{
	auto device = graphics->GetDevice();
	
	Vertex vertices[4] =
	{
		{-1.f, +1.f},
		{+1.f, +1.f},
		{-1.f, -1.f},
		{+1.f, -1.f},
	};

	D3D11_BUFFER_DESC vertex_buffer_desc = { 0 };
	vertex_buffer_desc.StructureByteStride = sizeof(Vertex);
	vertex_buffer_desc.ByteWidth = static_cast<UINT>(sizeof(Vertex) * std::size(vertices));
	vertex_buffer_desc.BindFlags = D3D11_BIND_VERTEX_BUFFER;
	vertex_buffer_desc.Usage = D3D11_USAGE_DEFAULT;

	D3D11_SUBRESOURCE_DATA vertex_init_data = { 0 };
	vertex_init_data.pSysMem = vertices;
	HRESULT hr = device->CreateBuffer(&vertex_buffer_desc, &vertex_init_data, &vertex_buffer);
	if (FAILED(hr))
		return false;

	using Index = unsigned short;
	Index indices[] =
	{
		0, 1, 2, 2, 1, 3,
	};

	D3D11_BUFFER_DESC index_buffer_desc = { 0 };
	index_buffer_desc.StructureByteStride = sizeof(Index);
	index_buffer_desc.ByteWidth = static_cast<UINT>(sizeof(Index) * std::size(indices));
	index_buffer_desc.BindFlags = D3D11_BIND_INDEX_BUFFER;
	index_buffer_desc.Usage = D3D11_USAGE_DEFAULT;

	D3D11_SUBRESOURCE_DATA index_init_data = { 0 };
	index_init_data.pSysMem = indices;
	hr = device->CreateBuffer(&index_buffer_desc, &index_init_data, &index_buffer);
	if (FAILED(hr))
		return false;

	D3D11_BUFFER_DESC cbuffer_desc = { 0 };
	cbuffer_desc.ByteWidth = sizeof(camera_cbuffer);
	cbuffer_desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
	cbuffer_desc.Usage = D3D11_USAGE_DYNAMIC;
	cbuffer_desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
	hr = device->CreateBuffer(&cbuffer_desc, nullptr, &camera_buffer);
	if (FAILED(hr))
		return false;

	return true;
}


void Application::render()
{
	float clear_color[4] = {0.2f, 0.f, 0.f, 0.f};
	auto ctx = graphics->GetContext();
	ctx->ClearRenderTargetView(graphics->GetMainRendertargetView(), clear_color);
	ctx->ClearDepthStencilView(graphics->GetMainDepthStencilView(), D3D11_CLEAR_DEPTH | D3D11_CLEAR_STENCIL, 1.f, 0);

	D3D11_MAPPED_SUBRESOURCE sub;
	ctx->Map(camera_buffer, 0, D3D11_MAP_WRITE_DISCARD, 0, &sub);
	camera_cbuffer *cam_buf = static_cast<camera_cbuffer *>(sub.pData);
	cam_buf->eye = camera.GetEye();
	cam_buf->front_vec = camera.GetDirection();
	cam_buf->right_vec = (camera.GetFrustrumEdge(0) - camera.GetFrustrumEdge(3)) * 0.5f;
	cam_buf->top_vec = (camera.GetFrustrumEdge(0) - camera.GetFrustrumEdge(1)) * 0.5f;

	ctx->Unmap(camera_buffer, 0);
	ctx->PSSetConstantBuffers(0, 1, &camera_buffer);

	UINT v_strides[] =
	{
		sizeof(Vertex),
	};
	UINT v_offsets[] =
	{
		0,
	};
	ID3D11Buffer *vertex_buffers[] =
	{
		vertex_buffer,
	};
	ctx->IASetVertexBuffers(0, 1, vertex_buffers, v_strides, v_offsets);
	ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

	ctx->IASetIndexBuffer(index_buffer, DXGI_FORMAT_R16_UINT, 0);

	ctx->DrawIndexed(6, 0, 0);

	graphics->Present();
	graphics->WaitForVBlank();
}


void Application::updateSimulation(float dt)
{
	stime += dt;

	Vector3 move = Vector3::NullVector();
	if (keystate['W'])
	{
		move += Vector3(0.f, 0.f, +1.f);
	}
	if (keystate['S'])
	{
		move += Vector3(0.f, 0.f, -1.f);
	}
	if (keystate['A'])
	{
		move += Vector3(-1.f, 0.f, 0.f);
	}
	if (keystate['D'])
	{
		move += Vector3(+1.f, 0.f, 0.f);
	}
	if (keystate['Q'])
	{
		move += Vector3(0.f, +1.f, 0.f);
	}
	if (keystate['E'])
	{
		move += Vector3(0.f, -1.f, 0.f);
	}

	camera.MoveRel(move * dt);
}
