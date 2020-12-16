---
layout: post
title: Setting up Resilience4j Circuit Breaker for Grpc Java Client
author: alicanhaman
categories: [grpc, resilience4j]
tags: [grpc, resilience4j, spring boot]
---

In this article, I will explain how to set up [Resilience4j](https://github.com/resilience4j/resilience4j) circuit breaker to work with a grpc client set up with [grpc-spring-boot-starter](https://github.com/yidongnan/grpc-spring-boot-starter). Normally, resilience4j is built to handle restful requests easily, but when it comes to grpc is [falls short](https://github.com/resilience4j/resilience4j/issues/1067). There is an open PR in the resilience4j repository, but it seems to have been left to rot.

First lets briefly mention our stack: 

- **Resilience4j** is a lightweight fault tolerance library inspired by [Netflix Hystrix](https://github.com/Netflix/Hystrix), but designed for Java 8 and functional programming. Lightweight, because the library only uses Vavr, which does not have any other external library dependencies. Netflix Hystrix, in contrast, has a compile dependency to Archaius which has many more external library dependencies such as Guava and Apache Commons Configuration. Since Hytrix have been moved to about 2 years ago, this library is deemed as a good alternative.
- **gRPC** is a modern open source high performance RPC framework that can run in any environment. It can efficiently connect services in and across data centers with pluggable support for load balancing, tracing, health checking and authentication.

## Dependencies

``` xml
<dependencies>
  <dependency>
      <groupId>net.devh</groupId>
      <artifactId>grpc-client-spring-boot-starter</artifactId>
  </dependency>
  <!-- basically your grpc proto project -->
  <dependency>
      <groupId>com.deepnetwork</groupId>
      <artifactId>simple-service-grpc</artifactId>
      <version>${project.version}</version>
  </dependency>
  <dependency>
      <groupId>io.github.resilience4j</groupId>
      <artifactId>resilience4j-spring-boot2</artifactId>
  </dependency>
</dependencies>
```

## Configuration
And an simple for resilience4j configuration that belongs in `application.yml`

``` yml
resilience4j.circuitbreaker:
  configs:
    default:
      registerHealthIndicator: true
      slidingWindowSize: 10
      minimumNumberOfCalls: 5
      permittedNumberOfCallsInHalfOpenState: 3
      automaticTransitionFromOpenToHalfOpenEnabled: true
      waitDurationInOpenState: 5s
      failureRateThreshold: 50
      eventConsumerBufferSize: 10
      recordExceptions:
        - io.grpc.StatusRuntimeException
  instances:
    simpleService:
      baseConfig: default
```

## Spring boot service that makes grpc client call

With resilience4j-spring-boot2 library it is extremely simple to add circuitbreaker to a service call just adding `@CircuitBreaker(name = "simpleService")` to a method will do the trick. Other than that I will also convert java object to grpc request and response to a meaningful java object.

``` java
@Service
public class SimpleServiceImpl implements SimpleService {

    @GrpcClient("simple-service")
    private SimpleServiceGrpc.SimpleServiceBlockingStub simpleServiceBlockingStub;
    private static final String simple_SERVICE = "simpleService";

    private final DomToGrpcRequestConverter domToGrpcRequestConverter;

    private final GrpcResponseToDomConverter grpcResponseToDomConverter;

    public SimpleServiceImpl(DomToGrpcRequestConverter domToGrpcRequestConverter, GrpcResponseToDomConverter grpcResponseToDomConverter) {
        this.domToGrpcRequestConverter = domToGrpcRequestConverter;
        this.grpcResponseToDomConverter = grpcResponseToDomConverter;
    }

    @CircuitBreaker(name = simple_SERVICE)
    @Override
    public SimpleMetadataDom onboard(SimpleOnboardDom simpleOnboardDom) {
        SimpleOnboardRequest simpleOnboardRequest = domToGrpcRequestConverter.createSimpleOnboardRequest(simpleOnboardDom);
        SimpleOnboardResponse simpleOnboardResponse = simpleServiceBlockingStub.onboardSimple(simpleOnboardRequest);
        return grpcResponseToDomConverter.createSimpleMetadataDom(simpleOnboardResponse);
    }
```

## Intercepting calls and fine tuning circuitbreaker

The ClientInterceptor will intercept every single call to client. If the CircuitBreaker is in closed or half-closed state call will be permitted and grpc request can continue on.
<p>
It will also add a custom listener to every single grpc call that has gone through checking the status of the grpc response. If it is a server side error it will be judged as circuitBreaker error, otherwise it will be judged as success. Therefore helping circuitBreaker decide when it needs to close.

``` java
public final class CircuitBreakerClientInterceptor implements ClientInterceptor {

    private final CircuitBreaker circuitBreaker;

    public CircuitBreakerClientInterceptor(CircuitBreaker circuitBreaker) {
        super();
        this.circuitBreaker = circuitBreaker;
    }

    @Override
    public <ReqT, RespT> ClientCall<ReqT, RespT> interceptCall(
            MethodDescriptor<ReqT, RespT> method, CallOptions callOptions, Channel next) {
        return new CheckedForwardingClientCall(next.newCall(method, callOptions)) {

            @Override
            protected void checkedStart(ClientCall.Listener responseListener, io.grpc.Metadata headers) {
                if (CircuitBreakerUtil.isCallPermitted(circuitBreaker))
                    this.delegate().start(new CircuitBreakerClientInterceptor.Listener(responseListener, System.nanoTime()), headers);
            }
        };
    }

    private final class Listener extends SimpleForwardingClientCallListener {
        private final long startedAt;
        // Server errors are taken from table in https://cloud.google.com/apis/design/errors
        private final Set<Status.Code> serverErrorStatusSet = Set.of(
                Status.Code.DATA_LOSS,
                Status.Code.UNKNOWN,
                Status.Code.INTERNAL,
                Status.Code.UNIMPLEMENTED,
                Status.Code.UNAVAILABLE,
                Status.Code.DEADLINE_EXCEEDED
        );

        public Listener(io.grpc.ClientCall.Listener delegate, long startedAt) {
            super(delegate);
            this.startedAt = startedAt;
        }

        @Override
        public void onClose(Status status, io.grpc.Metadata trailers) {
            long elapsed = System.nanoTime() - startedAt;
            // If the status code is not a server error status code add a success to circuitBreaker
            if (!serverErrorStatusSet.contains(status.getCode())) {
                CircuitBreakerClientInterceptor.this.circuitBreaker.onSuccess(elapsed, TimeUnit.NANOSECONDS);
            } else {
                CircuitBreakerClientInterceptor.this.circuitBreaker.onError(elapsed, TimeUnit.NANOSECONDS,
                        new StatusRuntimeException(status, trailers));
            }

            super.onClose(status, trailers);
        }
    }
}
```

## Configuring the grpc client for interceptor

We will also need to make the grpc client use our interceptor, there are some examples for that in [grpc-spring-boot-starter/examples](https://github.com/yidongnan/grpc-spring-boot-starter/tree/master/examples)

It will basically look like this
``` java
@Configuration(proxyBeanMethods = false)
public class GlobalClientInterceptorConfiguration {

    private static final String SIMPLE_SERVICE = "simpleService";
    protected final CircuitBreakerRegistry circuitBreakerRegistry;

    public GlobalClientInterceptorConfiguration(CircuitBreakerRegistry circuitBreakerRegistry) {
        this.circuitBreakerRegistry = circuitBreakerRegistry;
    }

    @GrpcGlobalClientInterceptor
    ClientInterceptor circuitBreakerClientInterceptor() {
        return new CircuitBreakerClientInterceptor(circuitBreakerRegistry.circuitBreaker(SIMPLE_SERVICE));
    }
}
```

## Final Words

That’s pretty much it from the article. I tried to summarize how to properly connect grpc with resilience4j. There isn't much information about this on the internet, this is what I managed to put together after some research. Hope it works for you too. Please don't hesitate to [connect](https://www.linkedin.com/in/alicanhaman/) / contact via alican.haman[at]deepnetwork.com.

## Further reading

If you are interested in how resilience4j works check out the [Getting Started Doc](https://resilience4j.readme.io/docs/getting-started-3) for resilience4j.

I would also recommend [this talk](https://www.youtube.com/watch?v=KosSsZEqS-k) by one of the contributors of the library. It explains in detail all the fault tolerance concepts in the library.

