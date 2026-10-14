package com.remine.server.controller;

import com.remine.server.dto.DeviceRegisterRequest;
import com.remine.server.dto.DeviceRegisterResponse;
import com.remine.server.service.DeviceService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/devices")
@RequiredArgsConstructor
public class DeviceController {

    private final DeviceService deviceService;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public DeviceRegisterResponse register(@Valid @RequestBody DeviceRegisterRequest request) {
        return deviceService.register(request);
    }
}
