package com.remine.server.auth;

import com.remine.server.exception.DeviceUnauthorizedException;
import com.remine.server.service.DeviceService;
import lombok.RequiredArgsConstructor;
import org.springframework.core.MethodParameter;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.support.WebDataBinderFactory;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.method.support.ModelAndViewContainer;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.util.List;

/** {@link CurrentDevice} 파라미터를 채운다. 토큰 값은 어디에도 남기지 않는다(예외 메시지·로그 포함). */
@Component
@RequiredArgsConstructor
public class CurrentDeviceResolver implements HandlerMethodArgumentResolver, WebMvcConfigurer {

    private static final String BEARER = "Bearer ";

    private final DeviceService deviceService;

    @Override
    public void addArgumentResolvers(List<HandlerMethodArgumentResolver> resolvers) {
        resolvers.add(this);
    }

    @Override
    public boolean supportsParameter(MethodParameter parameter) {
        return parameter.hasParameterAnnotation(CurrentDevice.class);
    }

    @Override
    public Long resolveArgument(MethodParameter parameter, ModelAndViewContainer mavContainer,
                                NativeWebRequest request, WebDataBinderFactory binderFactory) {
        String header = request.getHeader(HttpHeaders.AUTHORIZATION);
        Long deviceId = header != null && header.startsWith(BEARER)
                ? deviceService.authenticate(header.substring(BEARER.length()).strip()).orElse(null)
                : null;
        if (deviceId == null && parameter.getParameterAnnotation(CurrentDevice.class).required()) {
            throw new DeviceUnauthorizedException();
        }
        return deviceId;
    }
}
